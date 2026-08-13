class BillingCommission < ApplicationRecord
  belongs_to :tenant
  belongs_to :billing_affiliate
  belongs_to :billing_affiliate_attribution
  belongs_to :invoice

  normalizes :currency, with: ->(currency) { currency.strip.upcase }

  validates :currency, presence: true, length: { is: 3 }
  validates :basis_cents, :amount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :status, inclusion: { in: %w[pending approved paid void] }
  validates :earned_at, presence: true

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
end
