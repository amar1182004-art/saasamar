class SupportMessage < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :support_ticket
  belongs_to :author_user, class_name: "User", optional: true
  has_many :support_attachments, dependent: :restrict_with_exception

  normalizes :body, with: ->(value) { value.strip }

  validates :author_type, inclusion: { in: %w[merchant support system] }
  validates :body, presence: true, length: { maximum: 5_000 }
  validate :author_identity_matches_type

  private

  def author_identity_matches_type
    valid = case author_type
            when "merchant"
              author_user_id.present? && author_control_plane_user_id.blank?
            when "support"
              author_user_id.blank? && author_control_plane_user_id.present?
            when "system"
              author_user_id.blank? && author_control_plane_user_id.blank?
            else
              false
            end
    errors.add(:author_type, "does not match the author identity") unless valid
  end
end
