class Store < ApplicationRecord
  belongs_to :tenant

  normalizes :slug, with: ->(slug) { slug.strip.downcase }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :tenant_id, case_sensitive: false }
  validates :status, inclusion: { in: %w[draft active suspended closed] }
end
