require "test_helper"
require "tmpdir"

class Writebook::EpubExporterTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname.new(Dir.mktmpdir)
    @book = books(:handbook)
    @book.update!(published: true, author: "37signals", subtitle: "A field guide")
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "builds a valid EPUB container with one chapter per leaf" do
    result = build_epub

    Zip::File.open(epub_path) do |zip|
      entries = zip.entries

      assert_equal "mimetype", entries.first.name
      assert_equal Zip::Entry::STORED, entries.first.compression_method
      assert_equal "application/epub+zip", entries.first.get_input_stream.read

      assert zip.find_entry("META-INF/container.xml")
      assert zip.find_entry("OEBPS/content.opf")
      assert zip.find_entry("OEBPS/nav.xhtml")
      assert zip.find_entry("OEBPS/toc.ncx")
      assert zip.find_entry("OEBPS/text/title.xhtml")

      opf = zip.read("OEBPS/content.opf")
      assert_includes opf, "<dc:title>Handbook</dc:title>"
      assert_includes opf, "<dc:creator>37signals</dc:creator>"
      assert_includes opf, %(<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />)
      assert_includes opf, %(<spine toc="ncx">)

      chapter = zip.read("OEBPS/text/chapter-2.xhtml")
      assert_includes chapter, %(<html xmlns="http://www.w3.org/1999/xhtml")
      assert_includes chapter, "This is"
      assert_includes chapter, "Welcome to The Handbook"
      assert_not_includes chapter, "/u/", "in-body image URLs should be localized"

      nav = zip.read("OEBPS/nav.xhtml")
      @book.leaves.active.positioned.each do |leaf|
        assert_includes nav, leaf.title
      end

      Nokogiri::XML(chapter) { |config| config.strict }
    end

    assert_equal @book.leaves.active.count, result.chapters
    assert_operator result.bytes, :>, 0
    assert_equal 0, result.failures
  end

  test "embeds picture leaf images and in-body uploads" do
    markdown = pages(:welcome).body
    markdown.uploads.attach io: Rails.root.join("test/fixtures/files/reading.webp").open,
      filename: "reading.webp", content_type: "image/webp"
    attachment = markdown.uploads.attachments.last
    pages(:welcome).update!(body: "This is _such_ a great handbook.\n\n![Reading](/u/#{attachment.slug})")

    result = build_epub

    Zip::File.open(epub_path) do |zip|
      names = zip.entries.map(&:name)

      assert_includes names, "OEBPS/images/#{attachment.slug}"
      assert_operator zip.read("OEBPS/images/#{attachment.slug}").bytesize, :>, 0

      picture = leaves(:reading_picture).picture
      picture_name = "picture-#{picture.id}-#{picture.image.blob.filename}"
      assert_includes names, "OEBPS/images/#{picture_name}"
      assert_operator zip.read("OEBPS/images/#{picture_name}").bytesize, :>, 0

      welcome = zip.read("OEBPS/text/chapter-2.xhtml")
      assert_includes welcome, "src=\"../images/#{attachment.slug}\""

      reading = zip.read("OEBPS/text/chapter-4.xhtml")
      assert_includes reading, "src=\"../images/#{picture_name}\""

      opf = zip.read("OEBPS/content.opf")
      assert_includes opf, %(href="images/#{attachment.slug}")
      assert_includes opf, %(href="images/#{picture_name}")
    end

    assert_equal 2, result.images
    assert_equal 0, result.failures
  end

  test "embeds an attached cover and marks it as the EPUB cover" do
    @book.cover.attach io: Rails.root.join("test/fixtures/files/reading.webp").open,
      filename: "reading.webp", content_type: "image/webp"

    build_epub

    Zip::File.open(epub_path) do |zip|
      assert zip.find_entry("OEBPS/text/cover.xhtml")
      assert zip.find_entry("OEBPS/images/cover-reading.webp")

      opf = zip.read("OEBPS/content.opf")
      assert_includes opf, %(<item id="cover-image" href="images/cover-reading.webp" media-type="image/webp" properties="cover-image" />)
      assert_includes opf, %(<meta name="cover" content="cover-image" />)
      assert_includes opf, %(<itemref idref="cover-page" />)
    end
  end

  private
    def epub_path
      @dir.join("handbook.epub")
    end

    def build_epub
      Writebook::EpubExporter.new(@book, epub_path).call
    end
end
