require "test_helper"

class StaticExportsControllerTest < ActionDispatch::IntegrationTest
  # Mirrors StaticExportsController#static_dir, including the per-worker export
  # root parallel tests install (see test_helper.rb).
  def static_dir
    Rails.application.config.x.static_export_root.presence || Rails.root.join("tmp/static-site")
  end

  setup do
    # The exporter renders Book.published; publish the fixture book so the
    # generated site has something in it. Start from a clean output dir.
    books(:handbook).update!(published: true)
    FileUtils.rm_rf(static_dir)
  end

  teardown { FileUtils.rm_rf(static_dir) }

  test "show requires authentication" do
    get static_export_url
    assert_redirected_to new_session_url
  end

  test "create requires authentication" do
    post static_export_url
    assert_redirected_to new_session_url
  end

  test "non-admins are forbidden" do
    sign_in :kevin
    assert users(:kevin).member?

    get static_export_url
    assert_response :forbidden

    post static_export_url
    assert_response :forbidden

    get static_export_download_url
    assert_response :forbidden

    get static_site_preview_url
    assert_response :forbidden

    get static_export_result_url
    assert_response :forbidden
  end

  test "download and preview require authentication" do
    get static_export_download_url
    assert_redirected_to new_session_url

    get static_site_preview_url
    assert_redirected_to new_session_url
  end

  test "admin download streams a zip of the generated site" do
    sign_in :david

    get static_export_download_url
    assert_response :ok
    assert_match %r{application/zip}, response.content_type.to_s
    assert_match "PK", response.body # local-part of a zip file
  end

  test "admin preview serves the generated index" do
    sign_in :david

    get static_site_preview_url
    assert_response :ok
    assert_match %r{text/html}, response.content_type.to_s
    assert_match books(:handbook).title, response.body
  end

  test "admin create with no published books renders the nothing-to-export page" do
    sign_in :david
    Book.update_all(published: false)

    post static_export_url
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok
    assert_match "Nothing to export", response.body
    assert_no_match "Your static site is ready", response.body
  end

  test "admin create with no books at all renders empty even with drafts requested" do
    sign_in :david
    Book.destroy_all

    post static_export_url, params: { include_drafts: "1" }
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok
    assert_match "Nothing to export", response.body
  end

  test "admin create with drafts exports unpublished books and leaves the DB untouched" do
    sign_in :david
    books(:handbook).update!(published: false) # nothing published; handbook is now a draft

    post static_export_url, params: { include_drafts: "1" }
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok
    assert_match "Your static site is ready", response.body

    dir = static_dir
    book = books(:handbook)
    assert File.exist?(dir.join(book.id.to_s, book.slug, "index.html")),
      "the unpublished draft should have been exported"

    assert_equal false, Book.find(book.id).published,
      "the live database must be left untouched (draft still unpublished after rollback)"
  end

  test "admin show renders the landing page" do
    sign_in :david
    assert users(:david).administrator?

    get static_export_url
    assert_response :ok
    assert_match "Generate static site", @response.body
  end

  test "admin create renders the static site and the result page" do
    sign_in :david

    post static_export_url
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok

    dir = static_dir
    assert File.exist?(dir.join("index.html")), "expected the library index"

    book = books(:handbook)
    # The .md alternate routes are rendered too, so the alternate links resolve
    # instead of 404ing on the static host.
    assert File.exist?(dir.join(book.id.to_s, "#{book.slug}.md")),
      "expected the book markdown alternate"
    leaf = book.leaves.active.with_leafables.positioned.first
    assert File.exist?(dir.join(book.id.to_s, book.slug, leaf.id.to_s, "#{leaf.slug}.md")),
      "expected the leaf markdown alternate"

    assert_match "Your static site is ready", @response.body
    assert_match "Preview locally", @response.body
  end

  test "admin result without a stashed export falls back to the landing page" do
    sign_in :david

    get static_export_result_url
    assert_redirected_to static_export_url
  end

  test "result requires authentication" do
    get static_export_result_url
    assert_redirected_to new_session_url
  end

  test "admin show lists every book in the selector" do
    sign_in :david
    get static_export_url
    assert_response :ok
    assert_match "All published books", @response.body
    assert_match books(:handbook).title, @response.body
    assert_match books(:manual).title, @response.body
  end

  test "admin create with book_id exports only that book and leaves the DB untouched" do
    sign_in :david
    books(:handbook).update!(published: true)
    books(:manual).update!(published: true)

    post static_export_url, params: { book_id: books(:handbook).id }
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok
    assert_match "Your static site is ready", @response.body
    assert_match books(:handbook).title, @response.body

    dir = static_dir
    handbook = books(:handbook)
    manual = books(:manual)
    assert File.exist?(dir.join(handbook.id.to_s, handbook.slug, "index.html")),
      "the chosen book should have been exported"
    refute File.exist?(dir.join(manual.id.to_s, manual.slug, "index.html")),
      "the other published book should have been excluded"

    # The library menu shows only the chosen book.
    index = File.read(dir.join("index.html"))
    assert_match handbook.title, index
    refute_match manual.title, index

    # Live DB untouched: both books still published after the rollback.
    assert_equal true, Book.find(handbook.id).published
    assert_equal true, Book.find(manual.id).published
  end

  test "admin create with book_id exports a draft and leaves it a draft" do
    sign_in :david
    books(:handbook).update!(published: false) # the target is an unpublished draft
    books(:manual).update!(published: true)    # a published book that must be hidden

    post static_export_url, params: { book_id: books(:handbook).id }
    follow_redirect!
    assert_response :ok

    dir = static_dir
    handbook = books(:handbook)
    manual = books(:manual)
    assert File.exist?(dir.join(handbook.id.to_s, handbook.slug, "index.html")),
      "the chosen draft should be exported even though it isn't published"
    refute File.exist?(dir.join(manual.id.to_s, manual.slug, "index.html")),
      "the other published book should have been hidden during the export"

    assert_equal false, Book.find(handbook.id).published,
      "the live database must be left untouched (target still a draft)"
    assert_equal true, Book.find(manual.id).published,
      "the live database must be left untouched (other book still published)"
  end

  test "admin download with book_id names the zip after the book" do
    sign_in :david
    books(:handbook).update!(published: true)

    get static_export_download_url(book_id: books(:handbook).id)
    assert_response :ok
    assert_match %r{application/zip}, response.content_type.to_s
    assert_match "writebook-#{books(:handbook).slug}.zip",
                 response.headers["Content-Disposition"].to_s
  end

  test "admin create with export_format=markdown writes the markdown export and reports it" do
    sign_in :david

    post static_export_url, params: { export_format: "markdown" }
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok

    dir = static_dir
    book = books(:handbook)
    assert File.exist?(dir.join("index.md")), "expected the generated index.md"
    assert File.exist?(dir.join(book.slug, "#{book.slug}.md")), "expected the book markdown"
    assert_not File.exist?(dir.join("index.html")), "markdown export should not carry HTML"

    # The result page offers one download per exported book.
    assert_match "Your markdown export is ready", @response.body
    assert_match books(:handbook).title, @response.body
    assert_match %r{/static_export/download\?book_id=#{book.id}&amp;export_format=markdown}, @response.body
  end

  test "admin create with export_format=markdown exports a single book by id" do
    sign_in :david

    post static_export_url, params: { export_format: "markdown", book_id: books(:handbook).id }
    follow_redirect!
    assert_response :ok

    dir = static_dir
    handbook = books(:handbook)
    manual = books(:manual)
    assert File.exist?(dir.join(handbook.slug, "#{handbook.slug}.md"))
    assert_not File.exist?(dir.join(manual.slug, "#{manual.slug}.md")),
      "only the chosen book should be in the markdown export"

    assert_match handbook.title, @response.body
    refute_match manual.title, File.read(dir.join("index.md"))
  end

  test "admin download with export_format=markdown and book_id zips just that book's directory" do
    sign_in :david
    books(:handbook).update!(published: true)
    books(:manual).update!(published: true)

    post static_export_path, params: { export_format: "markdown" } # whole library
    follow_redirect!

    get static_export_download_path(book_id: books(:manual).id, export_format: "markdown")
    assert_response :ok
    assert_match %r{application/zip}, response.content_type.to_s
    assert_match "writebook-#{books(:manual).slug}-markdown.zip",
                 response.headers["Content-Disposition"].to_s

    # The archive carries only that book's flat directory.
    require "zip"
    Zip::File.open_buffer(response.body) do |zip|
      names = zip.entries.map(&:name)
      assert_includes names, "#{books(:manual).slug}/#{books(:manual).slug}.md"
      assert names.none? { |name| name.start_with?("#{books(:handbook).slug}/") },
        "the other book's files must not be in this book's zip"
    end
  end

  test "admin download with export_format=markdown names the zip accordingly" do
    sign_in :david

    get static_export_download_url(export_format: "markdown")
    assert_response :ok
    assert_match %r{application/zip}, response.content_type.to_s
    assert_match "writebook-static-site-markdown.zip",
                 response.headers["Content-Disposition"].to_s

    dir = static_dir
    assert File.exist?(dir.join("index.md")), "the download URL should regenerate as markdown when missing"
  end

  test "admin download with export_format=markdown regenerates when the directory holds html" do
    sign_in :david

    post static_export_url # HTML export first
    follow_redirect!
    assert File.exist?(static_dir.join("index.html"))

    # A hand-crafted markdown download URL (the result page's own link always
    # matches the generated format) explicitly asks for markdown, so the
    # exporter reruns in that format rather than zipping the wrong flavor.
    get static_export_download_url(export_format: "markdown")
    assert_response :ok
    assert_match %r{application/zip}, response.content_type.to_s

    dir = static_dir
    assert File.exist?(dir.join("index.md")), "the requested markdown export should have been regenerated"
  end

  test "an unknown export_format falls back to the html export" do
    sign_in :david

    post static_export_url, params: { export_format: "docx" }
    follow_redirect!
    assert_response :ok

    assert File.exist?(static_dir.join("index.html")),
      "an unknown format should fall back to the default html export"
    assert_match "Your static site is ready", @response.body
  end
end