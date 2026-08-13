class SupportAttachment < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :support_ticket
  belongs_to :support_message, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  normalizes :filename, with: ->(value) { value.strip }
  normalizes :object_key, with: ->(value) { value.strip }
  normalizes :content_type, with: ->(value) { value.strip.downcase }
  normalizes :checksum_sha256, with: ->(value) { value&.strip&.downcase&.presence }

  validates :kind, inclusion: { in: %w[file image video] }
  validates :filename, :object_key, :content_type, presence: true
  validates :byte_size, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[pending ready failed] }
  validates :checksum_sha256, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validate :creator_is_present

  scope :ready, -> { where(status: "ready") }

  private

  def creator_is_present
    return if created_by_user_id.present? || created_by_control_plane_user_id.present?

    errors.add(:base, "attachment creator is required")
  end
end
