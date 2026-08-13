class InventoryLedgerEntry < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :inventory_location
  belongs_to :product_variant
  belongs_to :actor_user, class_name: "User", optional: true

  normalizes :reason, with: ->(value) { value.strip }
  normalizes :reference_type, with: ->(value) { value&.strip&.presence }
  normalizes :idempotency_key, with: ->(value) { value.strip }

  validates :reason, presence: true
  validates :idempotency_key, presence: true
  validates :delta_on_hand, numericality: { only_integer: true }
  validates :delta_reserved, numericality: { only_integer: true }
  validate :has_nonzero_delta

  def readonly?
    persisted?
  end

  private

  def has_nonzero_delta
    return unless delta_on_hand.to_i.zero? && delta_reserved.to_i.zero?

    errors.add(:base, "inventory ledger entry must change stock")
  end
end
