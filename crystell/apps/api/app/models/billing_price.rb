class BillingPrice < ApplicationRecord
  belongs_to :billing_plan
  has_many :subscriptions, dependent: :restrict_with_exception

  normalizes :currency, with: ->(currency) { currency.strip.upcase }

  validates :currency, presence: true, length: { is: 3 }
  validates :interval, inclusion: { in: %w[monthly annual] }
  validates :status, inclusion: { in: %w[active archived] }
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
end
