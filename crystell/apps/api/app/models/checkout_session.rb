class CheckoutSession < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :cart
  belongs_to :selected_shipping_rate_quote, class_name: "ShippingRateQuote", optional: true
  has_many :checkout_line_items
  has_many :checkout_inventory_reservations, dependent: :restrict_with_exception
  has_one :order

  validates :status, inclusion: { in: %w[open inventory_reserved payment_pending completed expired cancelled] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :idempotency_key, presence: true
  validates :subtotal_cents, :discount_cents, :shipping_cents, :tax_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
