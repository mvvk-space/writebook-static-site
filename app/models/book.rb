class Book < ApplicationRecord
  include Accessable, Positionable, Sluggable

  has_many :leaves, dependent: :destroy
  has_one_attached :cover, dependent: :purge_later

  positioned_globally lock: ->(&block) { Current.account ? Current.account.with_lock(&block) : block.call }

  scope :ordered, -> { positioned }
  scope :published, -> { where(published: true) }

  enum :theme, %w[ black blue green magenta orange violet white ].index_by(&:itself), suffix: true, default: :blue

  def press(leafable, leaf_params)
    leaves.create! leaf_params.merge(leafable: leafable)
  end

  def markable
    leaves.active.positioned.map { it.leafable.markable }.join("\n\n")
  end
end
