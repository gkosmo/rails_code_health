class Post < ApplicationRecord
  # validates :title, presence: true  -- commented out for now
  # validates :body
  belongs_to :user
  has_many :comments
  validates :title, presence: true
end
