class InventoryLocation < ApplicationRecord
  belongs_to :tenant
  belongs_to :store

  has_many :inventory_levels, dependent: :restrict_with_exception
  has_many :inventory_ledger_entries, dependent: :restrict_with_exception
  has_many :inventory_reservations, dependent: :restrict_with_exception

  normalizes :name, with: ->(value) { value.strip }
  normalizes :code, with: ->(value) { value.strip.downcase }

  validates :name, presence: true
  validates :code, presence: true
  validates :status, inclusion: { in: %w[active inactive] }
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
