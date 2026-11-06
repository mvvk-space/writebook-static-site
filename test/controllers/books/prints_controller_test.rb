require "test_helper"

class Books::PrintsControllerTest < ActionDispatch::IntegrationTest
  setup do
    books(:handbook).update!(published: true)
  end

  test "renders a whole published book as one printable document" do
    book = books(:handbook)

    get book_print_path(book)

    assert_response :success
    assert_in_body book.title
    assert_match %r{/assets/print-}, response.body
    assert_select ".print-leaf", count: book.leaves.active.count
    assert_select ".print-toc a", count: book.leaves.active.count

    book.leaves.active.with_leafables.positioned.each do |leaf|
      assert_in_body leaf.title
    end
  end

  test "is reachable without signing in when the book is published" do
    get book_print_path(books(:handbook))

    assert_response :success
  end

  test "hides unpublished books from logged-out visitors" do
    books(:handbook).update!(published: false)

    get book_print_path(books(:handbook))

    assert_response :not_found
  end

  test "shows an accessible draft to its editor" do
    books(:handbook).update!(published: false)
    sign_in :kevin

    get book_print_path(books(:handbook))

    assert_response :success
  end
end
