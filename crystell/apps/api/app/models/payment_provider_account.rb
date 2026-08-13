class PaymentProviderAccount < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  has_many :payment_intents, dependent: :restrict_with_exception
  has_many :payment_webhook_events, dependent: :restrict_with_exception

  CREDENTIAL_PURPOSE = "crystell:payment-provider-credentials:v1"
  WEBHOOK_SECRET_PURPOSE = "crystell:payment-provider-webhook-secret:v1"

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
      purpose: CREDENTIAL_PURPOSE,
      parse_json: true
    )
  end

  def credentials=(value)
    object = value.respond_to?(:to_h) ? value.to_h : nil
    raise ArgumentError, "credentials must be an object" unless object.is_a?(Hash)

    self.credentials_ciphertext = Payment::CredentialVault.encrypt(object, purpose: CREDENTIAL_PURPOSE)
  end

  def webhook_secret
    Payment::CredentialVault.decrypt(webhook_secret_ciphertext, purpose: WEBHOOK_SECRET_PURPOSE)
  end

  def webhook_secret=(value)
    secret = value.to_s
    raise ArgumentError, "webhook secret is required" if secret.blank?

    self.webhook_secret_ciphertext = Payment::CredentialVault.encrypt(secret, purpose: WEBHOOK_SECRET_PURPOSE)
  end
end
