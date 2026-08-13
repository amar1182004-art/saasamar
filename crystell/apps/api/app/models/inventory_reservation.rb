class InventoryReservation < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :inventory_location
  belongs_to :product_variant

  normalizes :reference_type, with: ->(value) { value&.strip&.presence }
  normalizes :idempotency_key, with: ->(value) { value.strip }

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :idempotency_key, presence: true
  validates :status, inclusion: { in: %w[active released consumed expired] }

  scope :active, -> { where(status: "active") }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
