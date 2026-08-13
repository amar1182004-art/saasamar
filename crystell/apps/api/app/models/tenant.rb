class Tenant < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :stores, dependent: :destroy
  has_many :tenant_invitations, dependent: :destroy
  has_many :subscriptions, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception
  has_many :usage_events, dependent: :restrict_with_exception
  has_many :usage_totals, dependent: :restrict_with_exception
  has_many :billing_events, dependent: :restrict_with_exception

  normalizes :slug, with: ->(slug) { slug.strip.downcase }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: %w[active suspended closed] }
end
