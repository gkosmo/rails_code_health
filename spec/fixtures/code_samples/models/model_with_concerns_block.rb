class Article < ApplicationRecord
  included do
    has_many :revisions
    validates :slug, presence: true
  end

  has_many :tags
  validates :title, presence: true
end
