require "test_helper"

class Book::PositionableTest < ActiveSupport::TestCase
  test "books are sorted in positioned order" do
    assert_equal [ books(:handbook), books(:manual) ], Book.positioned
  end

  test "ordered follows position_score rather than title" do
    books(:manual).update!(position_score: 0)

    assert_equal [ books(:manual), books(:handbook) ], Book.ordered
  end

  test "positioned and ordered return the same sequence" do
    assert_equal Book.positioned.to_a, Book.ordered.to_a
  end

  test "new books are inserted at the end" do
    book = Book.create!(title: "Newest")

    assert_equal book, Book.positioned.last
  end

  test "books can be moved to the start" do
    books(:manual).move_to_position(0)

    assert_equal [ books(:manual), books(:handbook) ], Book.positioned
  end

  test "books can be moved to the middle" do
    third = Book.create!(title: "Third")
    books(:manual).move_to_position(1)

    assert_equal [ books(:handbook), books(:manual), third ], Book.positioned
  end

  test "books can be moved to the end" do
    books(:handbook).move_to_position(99)

    assert_equal [ books(:manual), books(:handbook) ], Book.positioned
  end

  test "two consecutive moves leave a stable order" do
    books(:manual).move_to_position(0)
    books(:manual).move_to_position(1)
    assert_equal [ books(:handbook), books(:manual) ], Book.positioned

    books(:manual).move_to_position(0)
    assert_equal [ books(:manual), books(:handbook) ], Book.positioned
  end
end
