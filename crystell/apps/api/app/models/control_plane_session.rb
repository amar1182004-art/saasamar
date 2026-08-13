class ControlPlaneSession < ControlPlaneRecord
  self.table_name = "control_plane_sessions"

  belongs_to :control_plane_user
  has_many :control_plane_audit_events, dependent: :nullify

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> {
    where(revoked_at: nil)
      .where("expires_at > ?", Time.current)
      .where.not(mfa_verified_at: nil)
  }

  def active?
    revoked_at.nil? && expires_at.future? && mfa_verified_at.present?
  end

  def elevated?
    active? && privilege_elevated_until.present? && privilege_elevated_until.future?
  end
end
