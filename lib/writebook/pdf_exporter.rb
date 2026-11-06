require "base64"
require "nokogiri"
require "open3"
require "securerandom"
require "timeout"
require "uri"

module Writebook
  # Turns a rendered print page into a PDF with a headless Chromium.
  #
  # The page the controller renders is already the whole book: a title page,
  # a table of contents, and every leaf. This exporter makes that page
  # self-contained before handing it to the browser -- stylesheets, font files,
  # covers, and in-body images are fetched through the live request session and
  # inlined as data URIs -- so Chromium can print a local file without a server,
  # a login, or a network round trip.
  #
  # Chromium is deliberately the only external dependency: it prints the same
  # HTML and CSS the reader sees, which keeps the PDF faithful to the print
  # stylesheet. Set CHROMIUM_PATH when the binary isn't on PATH.
  class PdfExporter
    Result = Struct.new(:leaves, :images, :failures, :bytes, keyword_init: true)

    class BrowserMissing < StandardError; end
    class BrowserFailed < StandardError; end

    BROWSER_CANDIDATES = %w[chromium chromium-browser google-chrome google-chrome-stable chrome].freeze
    BROWSER_TIMEOUT = 120

    MIME_TYPES = {
      ".css" => "text/css",
      ".gif" => "image/gif",
      ".jpeg" => "image/jpeg",
      ".jpg" => "image/jpeg",
      ".otf" => "font/otf",
      ".png" => "image/png",
      ".svg" => "image/svg+xml",
      ".ttf" => "font/ttf",
      ".webp" => "image/webp",
      ".woff" => "font/woff",
      ".woff2" => "font/woff2"
    }.freeze

    CSS_URL_PATTERN = /url\(\s*(['"]?)([^'")]+)\1\s*\)/

    class << self
      def browser_path
        @browser_path ||= ENV["CHROMIUM_PATH"].presence || BROWSER_CANDIDATES.filter_map { |name| find_executable(name) }.first
      end

      def available?
        browser_path.present?
      end

      def reset_browser_path!
        @browser_path = nil
      end

      private
        def find_executable(name)
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
            .map { |directory| File.join(directory, name) }
            .find { |path| File.executable?(path) }
        end
    end

    def initialize(book, destination, html:, fetcher:, host: nil, browser: nil)
      @book = book
      @destination = Pathname.new(destination)
      @html = html
      @fetcher = fetcher
      @host = host
      @browser = browser
      @failures = 0
      @data_uris = {}
      @images = {}
    end

    def call
      @document = Nokogiri::HTML5(@html)

      inline_stylesheets
      inline_images
      remove_scripts_and_head_links
      write_source_html
      run_browser

      Result.new(leaves: @book.leaves.active.count, images: @images.size,
                 failures: @failures, bytes: File.size(@destination))
    ensure
      FileUtils.rm_rf(@work_dir) if @work_dir
    end

    private
      def inline_stylesheets
        @document.css("link[rel='stylesheet'][href]").each do |link|
          path = local_path(link["href"])
          css = path && fetch(path)

          if css
            style = Nokogiri::XML::Node.new("style", @document)
            style["data-source"] = link["href"]
            style.content = inline_css_urls(css, path)
            link.replace(style)
          elsif path
            record_failure("could not fetch stylesheet #{path}")
            link.remove
          end
        end
      end

      def inline_css_urls(css, stylesheet_path)
        directory = File.dirname(stylesheet_path)

        css.gsub(CSS_URL_PATTERN) do |match|
          quote = Regexp.last_match(1)
          url = Regexp.last_match(2)
          path = local_path(resolve_url(url, directory))
          uri = path && data_uri_for(path)

          uri ? "url(#{quote}#{uri}#{quote})" : match
        end
      end

      def resolve_url(url, directory)
        url.start_with?("/", "data:", "#") ? url : File.join(directory, url)
      end

      def inline_images
        @document.css("img[src]").each do |image|
          path = local_path(image["src"])
          next if path.nil?

          if (uri = data_uri_for(path))
            image["src"] = uri
          else
            record_failure("could not fetch image #{path}")
            image.remove
          end

          image.remove_attribute("srcset")
        end
      end

      def remove_scripts_and_head_links
        @document.css("script").remove
        @document.css("link[rel='manifest'], link[rel='icon'], link[rel='apple-touch-icon'], link[rel='modulepreload']").remove
      end

      def data_uri_for(path)
        return @data_uris[path] if @data_uris.key?(path)

        bytes = fetch(path)
        return @data_uris[path] = nil if bytes.nil?

        media_type = media_type_for(path)
        @images[path] = true if media_type.start_with?("image/")
        @data_uris[path] = "data:#{media_type};base64,#{Base64.strict_encode64(bytes)}"
      end

      def media_type_for(path)
        extension = File.extname(path.split("?").first).downcase
        MIME_TYPES.fetch(extension, "application/octet-stream")
      end

      def local_path(url)
        url = url.to_s
        return if url.blank? || url.start_with?("#")

        uri = URI.parse(url)
        return if uri.scheme && !%w[http https].include?(uri.scheme)

        if uri.host.nil?
          url
        elsif uri.host == @host
          uri.request_uri
        end
      rescue URI::InvalidURIError
        nil
      end

      def fetch(path)
        @fetcher.call(path)
      end

      def write_source_html
        @work_dir = Rails.root.join("tmp", "pdf-export-#{Process.pid}-#{SecureRandom.hex(6)}")
        @work_dir.mkpath
        @source = @work_dir.join("index.html")
        @source.write(@document.to_html)
      end

      def run_browser
        browser = @browser.presence || self.class.browser_path
        raise BrowserMissing, "Chromium is not installed; set CHROMIUM_PATH to the browser binary" if browser.blank?

        @destination.dirname.mkpath
        output, status = Timeout.timeout(BROWSER_TIMEOUT) { Open3.capture2e(*browser_command(browser)) }

        unless status.success? && @destination.exist? && File.size(@destination).positive?
          raise BrowserFailed, "Chromium could not render the PDF: #{output.lines.last(5).join.strip}"
        end
      rescue Timeout::Error
        raise BrowserFailed, "Chromium timed out after #{BROWSER_TIMEOUT} seconds"
      end

      def browser_command(browser)
        [
          browser,
          "--headless=new",
          "--no-sandbox",
          "--disable-gpu",
          "--disable-dev-shm-usage",
          "--no-pdf-header-footer",
          "--run-all-compositor-stages-before-draw",
          "--virtual-time-budget=10000",
          "--print-to-pdf=#{@destination.expand_path}",
          "file://#{@source.expand_path}"
        ]
      end

      def record_failure(message)
        @failures += 1
        Rails.logger.warn("PDF export: #{message}")
      end
  end
end
