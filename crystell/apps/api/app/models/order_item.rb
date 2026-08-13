class OrderItem < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :order
  belongs_to :product, optional: true
  belongs_to :product_variant, optional: true

  validates :product_title, :variant_title, presence: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :line_subtotal_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
