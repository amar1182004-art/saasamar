class ShipmentEvent < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :shipment

  validates :event_type, presence: true
  validates :occurred_at, presence: true
end
