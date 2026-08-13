class Shipment < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :order
  belongs_to :shipping_provider_account
  has_many :shipment_events, dependent: :restrict_with_exception

  validates :status, inclusion: { in: %w[pending submitted label_ready in_transit delivered failed cancelled] }
  validates :service_code, :idempotency_key, presence: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :shipping_cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
