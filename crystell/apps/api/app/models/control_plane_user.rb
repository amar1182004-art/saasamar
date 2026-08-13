class ControlPlaneUser < ControlPlaneRecord
  self.table_name = "control_plane_users"

  has_secure_password

  has_many :control_plane_sessions, dependent: :destroy
  has_many :control_plane_audit_events, dependent: :nullify

  normalizes :email, with: ->(email) { email&.strip&.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: %w[active suspended] }
  validates :role, inclusion: { in: %w[viewer operator admin owner] }
  validates :password, length: { minimum: 16 }, allow_nil: true
  validates :mfa_secret_ciphertext, presence: true, if: :mfa_enabled?

  def mfa_secret
    return if mfa_secret_ciphertext.blank?

    ControlPlane::CredentialVault.decrypt(
      mfa_secret_ciphertext,
      purpose: "crystell:control-plane:mfa:v1"
    )
  end

  def mfa_secret=(value)
    secret = value.to_s
    raise ArgumentError, "MFA secret is required" if secret.blank?

    self.mfa_secret_ciphertext = ControlPlane::CredentialVault.encrypt(
      secret,
      purpose: "crystell:control-plane:mfa:v1"
    )
  end

  def mfa_enabled?
    mfa_enabled_at.present?
  end
end
