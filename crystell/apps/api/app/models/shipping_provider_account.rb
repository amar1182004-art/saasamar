class ShippingProviderAccount < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  has_many :shipping_rate_quotes, dependent: :restrict_with_exception
  has_many :shipments, dependent: :restrict_with_exception

  CREDENTIAL_PURPOSE = "crystell:shipping-provider-credentials:v1"

  normalizes :provider_key, with: ->(value) { value&.strip&.downcase }
  normalizes :display_name, with: ->(value) { value&.strip&.presence }

  validates :provider_key, presence: true, format: { with: /\A[a-z0-9][a-z0-9_.-]{1,63}\z/ }
  validates :mode, inclusion: { in: %w[test live] }
  validates :status, inclusion: { in: %w[active disabled] }
  validates :credentials_ciphertext, presence: true

  scope :active, -> { where(status: "active") }

  def credentials
    Shipping::CredentialVault.decrypt(credentials_ciphertext, purpose: CREDENTIAL_PURPOSE, parse_json: true)
  end

  def credentials=(value)
    object = value.respond_to?(:to_h) ? value.to_h : nil
    raise ArgumentError, "credentials must be an object" unless object.is_a?(Hash)

    self.credentials_ciphertext = Shipping::CredentialVault.encrypt(object, purpose: CREDENTIAL_PURPOSE)
  end
end
