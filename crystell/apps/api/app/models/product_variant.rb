class ProductVariant < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :product

  has_many :inventory_levels, dependent: :restrict_with_exception
  has_many :inventory_ledger_entries, dependent: :restrict_with_exception
  has_many :inventory_reservations, dependent: :restrict_with_exception
  has_many :product_media, class_name: "ProductMedia", dependent: :restrict_with_exception

  normalizes :title, with: ->(value) { value.strip }
  normalizes :sku, with: ->(value) { value&.strip&.presence }
  normalizes :barcode, with: ->(value) { value&.strip&.presence }
  normalizes :currency, with: ->(value) { value.strip.upcase }

  validates :title, presence: true
  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :compare_at_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :weight_grams, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, inclusion: { in: %w[active archived] }

  validate :compare_at_price_not_below_price

  private

  def compare_at_price_not_below_price
    return if compare_at_price_cents.nil? || price_cents.nil?
    return if compare_at_price_cents >= price_cents

    errors.add(:compare_at_price_cents, "must be greater than or equal to price")
  end
end
