class BillingFeature < ApplicationRecord
  has_many :billing_entitlements, dependent: :destroy
  has_many :billing_plans, through: :billing_entitlements
  has_many :usage_events, dependent: :restrict_with_exception
  has_many :usage_totals, dependent: :restrict_with_exception

  normalizes :key, with: ->(key) { key.strip.downcase }

  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :value_type, inclusion: { in: %w[boolean integer decimal string] }
end
