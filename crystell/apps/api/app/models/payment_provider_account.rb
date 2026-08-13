class PaymentProviderAccount < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  has_many :payment_intents, dependent: :restrict_with_exception
  has_many :payment_webhook_events, dependent: :restrict_with_exception

  normalizes :provider_key, with: ->(value) { value&.strip&.downcase }
  normalizes :display_name, with: ->(value) { value&.strip&.presence }

  validates :provider_key, presence: true, format: { with: /\A[a-z0-9][a-z0-9_.-]{1,63}\z/ }
  validates :mode, inclusion: { in: %w[test live] }
  validates :status, inclusion: { in: %w[active disabled] }
  validates :credentials_ciphertext, :webhook_secret_ciphertext, :webhook_endpoint_id, presence: true

  scope :active, -> { where(status: "active") }

  def credentials
    Payment::CredentialVault.decrypt(
      credentials_ciphertext,
      purpose: credential_purpose,
      parse_json: true
    )
  end

  def credentials=(value)
    object = value.respond_to?(:to_h) ? value.to_h : nil
    raise ArgumentError, "credentials must be an object" unless object.is_a?(Hash)

    self.credentials_ciphertext = Payment::CredentialVault.encrypt(object, purpose: credential_purpose)
  end

  def webhook_secret
    Payment::CredentialVault.decrypt(webhook_secret_ciphertext, purpose: webhook_secret_purpose)
  end

  def webhook_secret=(value)
    secret = value.to_s
    raise ArgumentError, "webhook secret is required" if secret.blank?

    self.webhook_secret_ciphertext = Payment::CredentialVault.encrypt(secret, purpose: webhook_secret_purpose)
  end

  private

  def credential_purpose
    "payment-provider-account:#{id || 'new'}:credentials"
  end

  def webhook_secret_purpose
    "payment-provider-account:#{id || 'new'}:webhook-secret"
  end
end
