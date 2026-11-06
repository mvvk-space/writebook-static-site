require "test_helper"

class Books::MovesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "an administrator moves a book" do
    post books_moves_url, params: { id: [ books(:manual).id ], position: 0 }
    assert_response :no_content

    assert_equal [ books(:manual), books(:handbook) ], Book.positioned
  end

  test "an administrator moves several books at once" do
    post books_moves_url, params: { id: [ books(:manual).id, books(:handbook).id ], position: 0 }
    assert_response :no_content

    assert_equal [ books(:manual), books(:handbook) ], Book.positioned
  end

  test "an unknown book is unprocessable" do
    post books_moves_url, params: { id: [ -1 ], position: 0 }

    assert_response :unprocessable_entity
  end

  test "a member is forbidden" do
    sign_in :kevin

    post books_moves_url, params: { id: [ books(:manual).id ], position: 0 }

    assert_response :forbidden
  end
end
