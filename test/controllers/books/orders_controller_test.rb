require "test_helper"

class Books::OrdersControllerTest < ActionDispatch::IntegrationTest
  test "an administrator sees the order page" do
    sign_in :david

    get books_order_url

    assert_response :success
    assert_select "figure.library__book", count: Book.count
  end

  test "a member is forbidden" do
    sign_in :kevin

    get books_order_url

    assert_response :forbidden
  end

  test "a signed-out visitor is asked to sign in" do
    get books_order_url

    assert_redirected_to new_session_url
  end
end
