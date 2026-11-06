class Books::SharesController < ApplicationController
  allow_unauthenticated_access only: :show

  include BookScoped

  def show
    @public_url = book_slug_url(@book)
  end
end
