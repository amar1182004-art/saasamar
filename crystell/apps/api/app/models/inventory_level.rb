class InventoryLevel < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :inventory_location
  belongs_to :product_variant

  validates :on_hand, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reserved, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :reserved_not_above_on_hand

  def available
    on_hand - reserved
  end

  private

  def reserved_not_above_on_hand
    return if on_hand.nil? || reserved.nil?
    return if reserved <= on_hand

    errors.add(:reserved, "cannot exceed on-hand quantity")
  end
end
