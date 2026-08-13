class ProductMedia < ApplicationRecord
  self.table_name = "product_media"

  belongs_to :tenant
  belongs_to :store
  belongs_to :product
  belongs_to :product_variant, optional: true

  normalizes :object_key, with: ->(value) { value.strip }
  normalizes :content_type, with: ->(value) { value.strip.downcase }
  normalizes :checksum_sha256, with: ->(value) { value&.strip&.downcase&.presence }
  normalizes :alt_text, with: ->(value) { value&.strip&.presence }

  validates :media_type, inclusion: { in: %w[image video] }
  validates :object_key, presence: true
  validates :content_type, presence: true
  validates :byte_size, numericality: { only_integer: true, greater_than: 0 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[pending ready failed] }
  validates :width, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :duration_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :checksum_sha256, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true

  validate :variant_belongs_to_product

  scope :ready, -> { where(status: "ready") }

  private

  def variant_belongs_to_product
    return if product_variant_id.blank? || product_id.blank?
    return if product_variant.nil? || product_variant.product_id == product_id

    errors.add(:product_variant_id, "must belong to the selected product")
  end
end
