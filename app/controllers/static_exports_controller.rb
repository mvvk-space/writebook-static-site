class StaticExportsController < ApplicationController
  # Generating a static copy of the library -- the whole thing or a single book
  # -- is a site-wide admin action: it renders books and copies every asset and
  # image blob they reference into a directory on the server. Non-admins get 403;
  # logged-out visitors are sent to sign in by the default authentication
  # before_action.
  before_action :ensure_can_administer

  # The landing page: explains what the export produces and offers the form
  # that POSTs to #create to run it. The form lets the operator pick "all
  # published books" (optionally with unpublished drafts) or a single book to
  # export by itself, so @books (every book, published or not) is loaded for the
  # selector -- a draft can be exported individually even though it isn't
  # published.
  def show
    @books = Book.ordered.to_a
  end

  # Renders the library to tmp/static-site (the same default the
  # static:generate rake task uses) and redirects to #result, which shows the
  # result with hosting steps. Two scopes, both rolled back so the live database
  # is untouched:
  #
  #   * Pass book_id=<id> to export a single book by itself, regardless of its
  #     published state. The library menu in the result shows just that book.
  #   * Otherwise export every published book. Pass include_drafts=1 to also
  #     include unpublished books.
  #
  # Pass export_format=markdown to write the markdown-only export instead of
  # the full HTML site (see Writebook::StaticExporter).
  #
  # Synchronous -- a published-only export takes seconds; operators with very
  # large libraries should use the rake task instead (noted on the landing page)
  # to avoid a request timeout.
  #
  # The redirect (PRG) is required because the landing form is Turbo-driven:
  # a Turbo form submission must receive a 3xx redirect. A 200 HTML response
  # (the former `render :create`) makes Turbo throw "Form responses must
  # redirect to another location". The result is stashed in the session and
  # rendered by the GET #result action, so the URL is also refresh-safe.
  def create
    export_format = export_format_param
    book = Book.find_by(id: params[:book_id].presence)

    if book
      result = generate(book: book, format: export_format)
      result.book_id = book.id
      result.book_title = book.title
      session[:static_export_result] = result.to_h.transform_keys(&:to_s)
    else
      include_drafts = params[:include_drafts] == "1"
      # Nothing to render: the library root itself redirects when there are no
      # published books, so short-circuit before the exporter would hit that.
      # (With drafts requested, an empty library -- no books at all -- is the
      # same. A bogus book_id also lands here, falling back to "nothing to
      # export" rather than 500ing.)
      if include_drafts ? Book.none? : Book.published.none?
        session[:static_export_result] = { "empty" => true }
      else
        result = generate(include_drafts: include_drafts, format: export_format)
        session[:static_export_result] = result.to_h.transform_keys(&:to_s)
      end
    end

    redirect_to static_export_result_url, status: :see_other
  end

  # GET: renders the result page stashed by #create. Refresh-safe -- the URL
  # stays valid until another export overwrites the session slot. A direct hit
  # with no stashed result (e.g. the session expired) falls back to the
  # landing page so the operator is never left on a dead URL.
  def result
    data = session[:static_export_result]
    if data.blank?
      redirect_to static_export_url, status: :see_other
      return
    end

    session.delete(:static_export_result)
    @output_dir = static_dir.expand_path
    if data["empty"]
      render :empty
    else
      @result = Writebook::StaticExporter::Result.new(**data.symbolize_keys)
      render :create
    end
  end

  # Streams the generated site as a .zip the operator can download from the
  # browser -- no server shell needed. Reuses the directory #create built;
  # regenerates first if it's absent (e.g. the operator bookmarked this URL).
  # A book_id query param (carried from the result page's download link) names
  # the .zip after the book and scopes a regeneration to just that book;
  # without it the whole library is exported. export_format=markdown (carried
  # from the result page the same way) both names the .zip differently and
  # scopes any regeneration to that format -- and with a book_id it zips just
  # that book's directory, so every book downloads as its own archive.
  def download
    export_format = export_format_param
    book = Book.find_by(id: params[:book_id].presence)
    ensure_static_site_generated(book: book, format: export_format)
    if book && export_format == "markdown"
      dir = exported_book_dir(book)
      unless static_dir.join(dir).directory?
        # The tree exists but this book's directory doesn't (pruned mid-preview,
        # or a stale tree from a differently-scoped export): regenerate scoped
        # to just this book, then re-resolve the (now clean) directory name.
        generate(book: book, format: export_format)
        dir = exported_book_dir(book)
      end
      send_file zip_static_site(scope: dir), filename: "writebook-#{dir}-markdown.zip",
                 type: "application/zip", disposition: "attachment"
    else
      if book
        filename = "writebook-#{book.slug}#{filename_suffix(export_format)}.zip"
      else
        filename = "writebook-static-site#{filename_suffix(export_format)}.zip"
      end
      send_file zip_static_site, filename: filename,
                 type: "application/zip", disposition: "attachment"
    end
  end

  # Serves the generated site from inside the running app so the operator can
  # see the export rendered in a browser tab without a server shell or a
  # separate web server. The directory is mapped under /static-site/ and any
  # path traversal is rejected.
  #
  # The static HTML uses root-relative URLs (/assets/..., /u/..., /rails/...).
  # Those resolve against the live app when the preview is served from a
  # subpath -- which is what we want, since the live app serves the same
  # precompiled assets and the same image blobs the export copied. The relative
  # sidebar fetch (../../_sidebar.html) and per-book files resolve within
  # /static-site/ and are served from the directory. The header CSP is cleared
  # so the static HTML's own <meta> policy governs, just like a real static host.
  def preview
    ensure_static_site_generated
    serve_preview_file
  end

  private
    # Where exports are written and served from. The default is tmp/static-site;
    # parallel test workers point config.x.static_export_root at per-worker
    # directories so they don't clobber each other's export (see test_helper.rb).
    def static_dir
      Rails.application.config.x.static_export_root.presence || Rails.root.join("tmp/static-site")
    end

    # Runs the exporter. The work is done in a separate thread wrapped in the
    # Rails executor: the exporter renders every page through a nested
    # ActionDispatch::Integration::Session, which re-enters the middleware
    # stack and resets ActiveSupport::CurrentAttributes. Running that nested
    # session inside the live request's thread would wipe the request's own
    # Current (and break the layout's `signed_in?`), so it runs in a thread
    # with its own CurrentAttributes scope instead. The thread is joined so the
    # request still returns the result synchronously.
    #
    # Two scopes, both inside a rolled-back transaction so the live database is
    # untouched:
    #
    #   * Pass a +book+ to export just that book: it's temporarily made the only
    #     published book, so the exporter (which reads `Book.published` and the
    #     library `/` route) renders the library menu and the book by itself,
    #     regardless of the book's real published state.
    #   * Otherwise, when +include_drafts+ is set, unpublished books are
    #     temporarily published so the exporter renders them -- the same
    #     approach as `bin/rails static:generate STATIC_ALL=1`.
    #
    # +format:+ selects the export flavor: "html" (the full self-contained
    # site, the default) or "markdown" (the markdown-only export).
    def generate(book: nil, include_drafts: false, format: Writebook::StaticExporter::DEFAULT_FORMAT)
      host = request.host
      protocol = request.ssl? ? "https" : "http"
      exporter = -> { Writebook::StaticExporter.new(static_dir, host: host, protocol: protocol, format: format).call }

      result = nil
      Thread.new do
        Rails.application.executor.wrap do
          if book
            Book.transaction do
              Book.where.not(id: book.id).update_all(published: false)
              book.update_columns(published: true)
              result = exporter.call
              raise ActiveRecord::Rollback
            end
          elsif include_drafts
            Book.transaction do
              Book.where(published: [ false, nil ]).update_all(published: true)
              result = exporter.call
              raise ActiveRecord::Rollback
            end
          else
            result = exporter.call
          end
        end
      end.join
      result
    end

    # Build the static site only when it isn't already on disk, so a direct hit
    # on download/preview still works without redoing the work #create did. When
    # a +book+ is given (a bookmarked single-book download URL), a regeneration
    # is scoped to just that book instead of the whole library. The sentinel
    # file differs per format: index.html for the HTML export, index.md for the
    # markdown export, so a stale directory of the other format triggers a
    # regeneration rather than serving the wrong flavor.
    def ensure_static_site_generated(book: nil, format: Writebook::StaticExporter::DEFAULT_FORMAT)
      sentinel = format == "markdown" ? "index.md" : "index.html"
      generate(book: book, format: format) unless static_dir.join(sentinel).exist?
    end

    # Coerces the export_format param to one of the exporter's known formats,
    # falling back to the default. Guards the download links and direct hits
    # against arbitrary param values.
    def export_format_param
      format = params[:export_format].presence
      Writebook::StaticExporter::FORMATS.include?(format) ? format : Writebook::StaticExporter::DEFAULT_FORMAT
    end

    # .zip filename discriminator for the markdown flavor; the HTML export
    # keeps the original names.
    def filename_suffix(format)
      format == "markdown" ? "-markdown" : ""
    end

    # The markdown export writes one flat directory per book, named after the
    # book's slug but deduped with -2, -3 suffixes when two exported books
    # share a title. The exporter records the id => directory mapping in
    # _book_dirs.json; read it back so a book-scoped download zips the right
    # directory even when the name differs from the book's own slug. Falls
    # back to the bare slug when no map exists (e.g. the directory was
    # regenerated scoped to just this book, where no collision can occur).
    def exported_book_dir(book)
      map_file = static_dir.join("_book_dirs.json")
      map = map_file.exist? ? JSON.parse(map_file.read) : {}
      map[book.id.to_s].presence || book.slug
    end

    # Zips the generated export. By default the whole tree lands under
    # static-site/ in the archive; pass +scope:+ to zip just one subdirectory,
    # with the archive entries under that directory's own name -- the markdown
    # export's per-book download zips one book's directory this way.
    def zip_static_site(scope: nil)
      require "zip"

      zip_path = Rails.root.join("tmp/writebook-static-site.zip")
      FileUtils.rm_f(zip_path)
      root = scope ? static_dir.join(scope) : static_dir
      prefix = scope || "static-site"

      Zip::File.open(zip_path, create: true) do |zip|
        Dir.glob(root.join("**", "*").to_s).each do |abs|
          next if File.directory?(abs)
          next unless File.exist?(abs) # a parallel worker may have pruned it mid-zip
          rel = Pathname.new(abs).relative_path_from(root).to_s
          zip.add("#{prefix}/#{rel}", abs)
        end
      end

      zip_path
    end

    def serve_preview_file
      rel = params[:path].presence || "index.html"
      raise ActionController::RoutingError, "not found" if rel.include?("..") || rel.start_with?("/")

      file = static_dir.join(rel)
      file = file.join("index.html") if file.directory?

      root = static_dir.expand_path.to_s
      unless file.file? && File.expand_path(file.to_s).start_with?("#{root}/")
        raise ActionController::RoutingError, "not found"
      end

      response.headers["Content-Security-Policy"] = nil
      send_file file.to_s, disposition: "inline"
    end
end
