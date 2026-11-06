require "test_helper"
require "tmpdir"

class Writebook::PdfExporterTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname.new(Dir.mktmpdir)
    @book = books(:handbook)
    @book.update!(published: true)
    @pdf_path = @dir.join("handbook.pdf")
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "renders a PDF from a print page" do
    skip "Chromium is not available" unless Writebook::PdfExporter.available?

    result = Writebook::PdfExporter.new(@book, @pdf_path, html: print_html, fetcher: ->(_path) { nil }).call

    assert_equal "%PDF", File.binread(@pdf_path, 4)
    assert_operator result.bytes, :>, 0
    assert_equal @book.leaves.active.count, result.leaves
    assert_equal 0, result.failures
  end

  test "inlines referenced images before printing" do
    skip "Chromium is not available" unless Writebook::PdfExporter.available?

    image = Rails.root.join("test/fixtures/files/white-rabbit.webp").binread
    html = print_html(image: "/u/white-rabbit.webp")
    fetcher = ->(path) { path == "/u/white-rabbit.webp" ? image : nil }

    result = Writebook::PdfExporter.new(@book, @pdf_path, html: html, fetcher: fetcher).call

    assert_equal 1, result.images
    assert_equal 0, result.failures
    assert_equal "%PDF", File.binread(@pdf_path, 4)
  end

  private
    def print_html(image: nil)
      img = image ? %(<img src="#{image}" alt="Reading">) : ""
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="UTF-8">
            <title>#{@book.title}</title>
            <style>@page { margin: 1in } body { font-family: serif }</style>
          </head>
          <body>
            <h1>#{@book.title}</h1>
            #{img}
            <p>Printable content.</p>
          </body>
        </html>
      HTML
    end
end
