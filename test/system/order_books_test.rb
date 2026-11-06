require "application_system_test_case"
require "timeout"

class OrderBooksTest < ApplicationSystemTestCase
  setup do
    sign_in "david@example.com"
  end

  test "reorder the library with the keyboard" do
    visit books_order_url

    check "arrange-mode", allow_label_click: true

    list = find("menu.library")
    list.send_keys :up
    page.send_keys :space
    page.send_keys :up
    page.send_keys :enter

    Timeout.timeout(5) do
      sleep 0.05 until Book.positioned.first == books(:manual)
    end

    visit books_order_url
    assert_equal [ "Manual", "Handbook" ], all("figure.library__book h2 strong").map(&:text)
  end
end
