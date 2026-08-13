class CheckoutInventoryReservation < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :checkout_session
  belongs_to :checkout_line_item
  belongs_to :product_variant
  belongs_to :inventory_location
  belongs_to :inventory_reservation

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
