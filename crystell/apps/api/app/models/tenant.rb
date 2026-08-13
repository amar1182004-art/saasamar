class Tenant < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :stores, dependent: :destroy
  has_many :tenant_invitations, dependent: :destroy

  normalizes :slug, with: ->(slug) { slug.strip.downcase }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: %w[active suspended closed] }
end
