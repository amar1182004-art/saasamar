class Product < ApplicationRecord
  belongs_to :tenant
  belongs_to :store

  has_many :product_variants, dependent: :restrict_with_exception
  has_many :product_category_assignments, dependent: :delete_all
  has_many :categories, through: :product_category_assignments

  normalizes :title, with: ->(value) { value.strip }
  normalizes :slug, with: ->(value) { value.strip.downcase }
  normalizes :vendor, with: ->(value) { value&.strip&.presence }
  normalizes :product_type, with: ->(value) { value&.strip&.presence }

  validates :title, presence: true
  validates :slug, presence: true
  validates :status, inclusion: { in: %w[draft active archived] }

  scope :published, -> { where(status: "active").where.not(published_at: nil).where("published_at <= ?", Time.current) }
end
