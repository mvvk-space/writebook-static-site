class Books::OrdersController < ApplicationController
  before_action :ensure_can_administer

  def show
    @books = Book.positioned
  end
end
