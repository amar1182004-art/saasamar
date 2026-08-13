class Order < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :checkout_session
  has_many :order_items

  validates :order_number, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[pending confirmed cancelled closed] }
  validates :payment_status, inclusion: { in: %w[unpaid pending authorized paid partially_refunded refunded failed] }
  validates :fulfillment_status, inclusion: { in: %w[unfulfilled partial fulfilled returned cancelled] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :subtotal_cents, :discount_cents, :shipping_cents, :tax_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
