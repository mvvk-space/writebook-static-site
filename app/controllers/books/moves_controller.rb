class Books::MovesController < ApplicationController
  before_action :ensure_can_administer

  def create
    book, *followed_by = books
    return head :unprocessable_entity unless book

    book.move_to_position(position, followed_by: followed_by)

    head :no_content
  rescue ActiveRecord::RecordNotFound
    head :unprocessable_entity
  end

  private
    def position
      params[:position].to_i
    end

    def books
      Book.find(Array(params[:id]))
    end
end
