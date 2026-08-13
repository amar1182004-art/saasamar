class TenantInvitation < ApplicationRecord
  belongs_to :tenant
  belongs_to :invited_by_user, class_name: "User"

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true
  validates :role, inclusion: { in: %w[admin member] }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(accepted_at: nil, revoked_at: nil).where("expires_at > ?", Time.current) }
end
