require "nokogiri"
require "securerandom"
require "zip"

module Writebook
  class EpubExporter
    Result = Struct.new(:chapters, :images, :failures, :bytes, keyword_init: true)

    LANGUAGE = "en"
    DEFAULT_PICTURE = Rails.root.join("app/assets/images/default-picture.webp")
    IMAGE_EXTENSIONS = {
      "image/jpeg" => "jpg",
      "image/png" => "png",
      "image/gif" => "gif",
      "image/webp" => "webp",
      "image/svg+xml" => "svg"
    }.freeze

    STYLE = <<~CSS
      body {
        font-family: serif;
        line-height: 1.5;
        margin: 0 5%;
      }

      h1, h2, h3, h4, h5, h6 {
        line-height: 1.2;
      }

      img {
        height: auto;
        max-width: 100%;
      }

      figure {
        margin: 2em 0;
        text-align: center;
      }

      figcaption {
        color: #555;
        font-style: italic;
        margin-top: 0.5em;
      }

      pre {
        overflow-x: auto;
        white-space: pre-wrap;
      }

      .book-title {
        font-size: 2.5em;
        margin-top: 20%;
        text-align: center;
      }

      .book-subtitle,
      .book-author {
        text-align: center;
      }

      .cover {
        margin: 0;
        padding: 0;
        text-align: center;
      }

      .cover img {
        max-height: 100%;
      }
    CSS

    def initialize(book, destination, fetcher: nil)
      @book = book
      @destination = Pathname.new(destination)
      @fetcher = fetcher
      @images = {}
      @image_keys = {}
      @leaf_hrefs = {}
      @failures = 0
    end

    def call
      @leaves = @book.leaves.active.with_leafables.positioned.to_a
      build_leaf_hrefs
      build_upload_index
      @chapters = build_chapters
      @cover_image = cover_image_name

      write_epub

      Result.new(chapters: @leaves.size, images: @images.size, failures: @failures, bytes: File.size(@destination))
    end

    private
      def build_leaf_hrefs
        book_path = "/#{@book.id}/#{@book.slug}"
        @leaf_hrefs[book_path] = "title.xhtml"
        @leaf_hrefs["#{book_path}/"] = "title.xhtml"

        @leaves.each_with_index do |leaf, index|
          href = chapter_filename(index)
          leaf_path = "#{book_path}/#{leaf.id}/#{leaf.slug}"
          @leaf_hrefs[leaf_path] = href
          @leaf_hrefs["#{leaf_path}/"] = href
        end
      end

      def build_upload_index
        @uploads = {}
        @leaves.each do |leaf|
          next unless leaf.page?

          markdown = leaf.page.body
          next unless markdown.respond_to?(:uploads)

          markdown.uploads.attachments.includes(:blob).each do |attachment|
            @uploads[attachment.slug] = attachment
          end
        end
      end

      def build_chapters
        @leaves.each_with_index.map do |leaf, index|
          { href: chapter_filename(index), title: leaf.title, body: chapter_body(leaf) }
        end
      end

      def chapter_filename(index)
        "chapter-#{index + 1}.xhtml"
      end

      def chapter_body(leaf)
        if leaf.page?
          clean_html(leaf.page.body.to_html)
        elsif leaf.section?
          clean_html(ActionController::Base.helpers.simple_format(leaf.section.body.to_s))
        elsif leaf.picture?
          picture_body(leaf)
        else
          ""
        end
      end

      def picture_body(leaf)
        picture = leaf.picture
        name = picture_image_name(picture)
        caption = picture.caption.to_s

        if name
          image = %(<img src="../images/#{name}" alt="#{escape(leaf.title)}" />)
          caption = "<figcaption>#{escape(caption)}</figcaption>" if caption.present?
          "<figure>#{image}#{caption}</figure>"
        elsif caption.present?
          "<p>#{escape(caption)}</p>"
        else
          ""
        end
      end

      def picture_image_name(picture)
        if picture.image.attached?
          blob = picture.image.blob
          add_image("picture:#{picture.id}", "picture-#{picture.id}-#{blob.filename}", blob.download, blob.content_type)
        else
          add_image("picture:default", "default-picture.webp", DEFAULT_PICTURE.binread, "image/webp")
        end
      rescue => error
        record_failure("picture #{picture.id}: #{error.message}")
        nil
      end

      def cover_image_name
        return unless @book.cover.attached?

        blob = @book.cover.blob
        add_image("cover:#{blob.id}", "cover-#{blob.filename}", blob.download, blob.content_type)
      rescue => error
        record_failure("cover: #{error.message}")
        nil
      end

      def clean_html(html)
        sanitized = ActionController::Base.helpers.sanitize(html.to_s, scrubber: HtmlScrubber.new)
        fragment = Nokogiri::HTML5.fragment(sanitized)

        fragment.css("a[href]").each do |anchor|
          href = anchor["href"].to_s
          if image_link?(href)
            anchor.replace(anchor.children)
          elsif !href.start_with?("#")
            anchor["href"] = rewrite_href(href)
          end
        end

        fragment.css("img[src]").each do |image|
          image["src"] = local_image_path(image["src"])
        end

        fragment.css("iframe").remove
        fragment.to_xhtml
      end

      def image_link?(href)
        href.start_with?("/u/", "/rails/active_storage/")
      end

      def rewrite_href(href)
        path, anchor = href.split("#", 2)
        target = @leaf_hrefs[path]
        return href unless target

        anchor.present? ? "#{target}##{anchor}" : target
      end

      def local_image_path(src)
        path = src.to_s.split("?").first
        return src if path.blank? || path.start_with?("data:", "http://", "https://")

        name = register_path_image(path)
        name ? "../images/#{name}" : src
      end

      def register_path_image(path)
        slug = File.basename(path)

        if (attachment = @uploads[slug])
          blob = attachment.blob
          add_image("upload:#{slug}", slug, blob.download, blob.content_type)
        elsif @fetcher && (bytes = @fetcher.call(path))
          add_image("path:#{path}", slug, bytes, media_type_for(slug))
        else
          record_failure("could not fetch #{path}")
          nil
        end
      rescue => error
        record_failure("#{path}: #{error.message}")
        nil
      end

      def add_image(key, filename, bytes, media_type)
        return @image_keys[key] if @image_keys.key?(key)

        name = unique_image_name(filename, media_type)
        @image_keys[key] = name
        @images[name] = { bytes: bytes, media_type: media_type.presence || media_type_for(name) }
        name
      end

      def unique_image_name(filename, media_type)
        base = File.basename(filename.to_s).gsub(/[^\w.\-]/, "-")
        base = "image" if base.blank?
        base += ".#{IMAGE_EXTENSIONS[media_type]}" if File.extname(base).blank? && IMAGE_EXTENSIONS[media_type]

        extension = File.extname(base)
        stem = extension.present? ? base.delete_suffix(extension) : base
        candidate = base
        suffix = 1

        while @images.key?(candidate)
          suffix += 1
          candidate = "#{stem}-#{suffix}#{extension}"
        end

        candidate
      end

      def media_type_for(filename)
        extension = File.extname(filename.to_s).delete_prefix(".").downcase
        IMAGE_EXTENSIONS.key(extension) || "application/octet-stream"
      end

      def record_failure(message)
        @failures += 1
        Rails.logger.warn("EPUB export: #{message}")
      end

      def write_epub
        @destination.dirname.mkpath

        Zip::OutputStream.open(@destination.to_s, suppress_extra_fields: true) do |stream|
          add_entry(stream, "mimetype", "application/epub+zip", stored: true)
          add_entry(stream, "META-INF/container.xml", container_xml)
          add_entry(stream, "OEBPS/content.opf", content_opf)
          add_entry(stream, "OEBPS/nav.xhtml", nav_xhtml)
          add_entry(stream, "OEBPS/toc.ncx", toc_ncx)
          add_entry(stream, "OEBPS/styles/style.css", STYLE)
          add_entry(stream, "OEBPS/text/title.xhtml", title_xhtml)
          add_entry(stream, "OEBPS/text/cover.xhtml", cover_xhtml) if @cover_image

          @chapters.each do |chapter|
            add_entry(stream, "OEBPS/text/#{chapter[:href]}", chapter_xhtml(chapter))
          end

          @images.each do |name, image|
            add_entry(stream, "OEBPS/images/#{name}", image[:bytes])
          end
        end
      end

      def add_entry(stream, name, body, stored: false)
        compression = stored ? Zip::Entry::STORED : Zip::Entry::DEFLATED
        stream.put_next_entry(name, nil, nil, compression)
        stream.write(body)
      end

      def container_xml
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
              <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml" />
            </rootfiles>
          </container>
        XML
      end

      def content_opf
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="#{LANGUAGE}">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:identifier id="book-id">#{identifier}</dc:identifier>
              <dc:title>#{escape(@book.title)}</dc:title>
              #{metadata_creator}
              #{metadata_description}
              <dc:language>#{LANGUAGE}</dc:language>
              <dc:date>#{escape(@book.updated_at.utc.iso8601)}</dc:date>
              <meta property="dcterms:modified">#{escape(@book.updated_at.utc.iso8601)}</meta>
              #{metadata_cover}
            </metadata>
            <manifest>
              <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />
              <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml" />
              <item id="style" href="styles/style.css" media-type="text/css" />
              <item id="title" href="text/title.xhtml" media-type="application/xhtml+xml" />
              #{manifest_cover}
              #{manifest_chapters}
              #{manifest_images}
            </manifest>
            <spine toc="ncx">
              #{spine_items}
            </spine>
          </package>
        XML
      end

      def metadata_creator
        return if @book.author.blank?
        "<dc:creator>#{escape(@book.author)}</dc:creator>"
      end

      def metadata_description
        return if @book.subtitle.blank?
        "<dc:description>#{escape(@book.subtitle)}</dc:description>"
      end

      def metadata_cover
        return unless @cover_image
        %(<meta name="cover" content="cover-image" />)
      end

      def manifest_cover
        if @cover_image
          %(<item id="cover-page" href="text/cover.xhtml" media-type="application/xhtml+xml" />\n    <item id="cover-image" href="images/#{@cover_image}" media-type="#{image_media_type(@cover_image)}" properties="cover-image" />)
        else
          ""
        end
      end

      def manifest_chapters
        @chapters.each_with_index.map do |chapter, index|
          %(<item id="chapter-#{index + 1}" href="text/#{chapter[:href]}" media-type="application/xhtml+xml" />)
        end.join("\n    ")
      end

      def manifest_images
        @images.reject { |name, _| name == @cover_image }.each_with_index.map do |(name, image), index|
          %(<item id="image-#{index + 1}" href="images/#{name}" media-type="#{image[:media_type]}" />)
        end.join("\n    ")
      end

      def spine_items
        items = [ %(<itemref idref="title" />) ]
        items.unshift(%(<itemref idref="cover-page" />)) if @cover_image
        items.concat(@chapters.each_index.map { |index| %(<itemref idref="chapter-#{index + 1}" />) })

        items.join("\n      ")
      end

      def nav_xhtml
        entries = [ [ "text/title.xhtml", "Title Page" ] ]
        entries.unshift([ "text/cover.xhtml", "Cover" ]) if @cover_image
        entries.concat(@chapters.map { |chapter| [ "text/#{chapter[:href]}", chapter[:title] ] })

        items = entries.map do |href, title|
          %(<li><a href="#{href}">#{escape(title)}</a></li>)
        end.join("\n        ")

        xhtml_document("Contents", <<~HTML, stylesheet: "styles/style.css")
          <nav epub:type="toc" id="toc">
            <h1>Contents</h1>
            <ol>
              #{items}
            </ol>
          </nav>
        HTML
      end

      def toc_ncx
        nav_points = navigation_entries.each_with_index.map do |(href, title), index|
          <<~XML
            <navPoint id="navpoint-#{index + 1}" playOrder="#{index + 1}">
              <navLabel><text>#{escape(title)}</text></navLabel>
              <content src="#{href}" />
            </navPoint>
          XML
        end.join

        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
            <head>
              <meta name="dtb:uid" content="#{escape(identifier)}" />
            </head>
            <docTitle><text>#{escape(@book.title)}</text></docTitle>
            <navMap>
              #{nav_points}
            </navMap>
          </ncx>
        XML
      end

      def navigation_entries
        entries = [ [ "text/title.xhtml", "Title Page" ] ]
        entries.unshift([ "text/cover.xhtml", "Cover" ]) if @cover_image
        entries.concat(@chapters.map { |chapter| [ "text/#{chapter[:href]}", chapter[:title] ] })
      end

      def title_xhtml
        author = @book.author.present? ? %(<p class="book-author">#{escape(@book.author)}</p>) : ""
        subtitle = @book.subtitle.present? ? %(<p class="book-subtitle">#{escape(@book.subtitle)}</p>) : ""

        xhtml_document(@book.title, <<~HTML)
          <section epub:type="titlepage">
            <h1 class="book-title">#{escape(@book.title)}</h1>
            #{subtitle}
            #{author}
          </section>
        HTML
      end

      def cover_xhtml
        body = <<~HTML
          <section class="cover" epub:type="cover">
            <img src="../images/#{@cover_image}" alt="#{escape(@book.title)}" />
          </section>
        HTML

        xhtml_document("Cover", body)
      end

      def chapter_xhtml(chapter)
        xhtml_document(chapter[:title], <<~HTML)
          <section epub:type="chapter">
            <h1>#{escape(chapter[:title])}</h1>
            #{chapter[:body]}
          </section>
        HTML
      end

      def xhtml_document(title, body, stylesheet: "../styles/style.css")
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE html>
          <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{LANGUAGE}">
            <head>
              <meta charset="utf-8" />
              <title>#{escape(title)}</title>
              <link rel="stylesheet" type="text/css" href="#{stylesheet}" />
            </head>
            <body>
              #{body}
            </body>
          </html>
        XML
      end

      def image_media_type(name)
        @images.dig(name, :media_type) || media_type_for(name)
      end

      def identifier
        @identifier ||= "urn:uuid:#{SecureRandom.uuid}"
      end

      def escape(value)
        ERB::Util.html_escape(value.to_s)
      end
  end
end
