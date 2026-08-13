class BillingPlan < ApplicationRecord
  has_many :billing_prices, dependent: :destroy
  has_many :billing_entitlements, dependent: :destroy
  has_many :billing_features, through: :billing_entitlements
  has_many :subscriptions, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.strip.downcase }

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :status, inclusion: { in: %w[draft active archived] }
  validates :trial_days, numericality: { greater_than_or_equal_to: 0, only_integer: true }
end
