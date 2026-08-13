class Notification < ApplicationRecord
  belongs_to :tenant
  belongs_to :store, optional: true
  belongs_to :user

  normalizes :kind, with: ->(value) { value.strip.downcase }
  normalizes :title, with: ->(value) { value.strip }
  normalizes :body, with: ->(value) { value.strip }

  validates :kind, format: { with: /\A[a-z0-9][a-z0-9._-]{0,119}\z/ }
  validates :title, presence: true, length: { maximum: 160 }
  validates :body, presence: true, length: { maximum: 2_000 }
  validates :action_url, length: { maximum: 2_000 }, allow_nil: true
end
