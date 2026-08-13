class CartItem < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :cart
  belongs_to :product_variant

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
