class BillingCouponRedemption < ApplicationRecord
  belongs_to :tenant
  belongs_to :billing_coupon
  belongs_to :subscription
  belongs_to :invoice, optional: true

  validates :idempotency_key, presence: true
  validates :discount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :redeemed_at, presence: true

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
end
