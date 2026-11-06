require "test_helper"

class Books::SharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @book = books(:handbook)
  end

  test "shares a published book with anyone" do
    @book.update!(published: true)

    get book_share_path(@book)

    assert_response :success
    assert_in_body "Share #{@book.title}"
    assert_in_body book_slug_url(@book)
    assert_select "img.qr-code[src*='/qr_code/']"
    assert_select "[data-controller='copy-to-clipboard']"
    assert_select "[data-controller='web-share']"
  end

  test "offers the per-book exports to an administrator" do
    @book.update!(published: true)
    sign_in :david

    get book_share_path(@book)

    assert_response :success
    assert_in_body book_print_path(@book)
    assert_in_body book_slug_path(@book, format: :md)
    %w[epub pdf html].each do |format|
      assert_select "a[href=?]", static_export_download_path(book_id: @book.id, export_format: format)
    end
  end

  test "hides the administrator exports from a member" do
    @book.update!(published: true)
    sign_in :kevin

    get book_share_path(@book)

    assert_response :success
    assert_select "a[href=?]", static_export_download_path(book_id: @book.id, export_format: "epub"), count: 0
  end

  test "explains that a draft has no public link, and offers exports to its editor" do
    sign_in :kevin

    get book_share_path(@book)

    assert_response :success
    assert_in_body "isn't published yet"
    assert_not_in_body book_slug_url(@book)
    assert_select "[data-controller='copy-to-clipboard']", count: 0
    assert_in_body book_print_path(@book)
  end

  test "hides an inaccessible draft" do
    @book.update!(published: false)

    get book_share_path(@book)

    assert_response :not_found
  end
end
