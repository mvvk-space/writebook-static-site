class Books::PrintsController < ApplicationController
  allow_unauthenticated_access only: :show

  include BookScoped

  def show
    @leaves = @book.leaves.active.with_leafables.positioned

    render layout: "print"
  end
end
