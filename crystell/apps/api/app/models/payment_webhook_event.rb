class PaymentWebhookEvent < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :payment_provider_account

  validates :provider_event_id, :event_type, :payload_digest, :signature_digest, :raw_body_ciphertext, presence: true
  validates :status, inclusion: { in: %w[received processed ignored failed] }

  def raw_body
    Payment::CredentialVault.decrypt(
      raw_body_ciphertext,
      purpose: "crystell:payment-webhook-body:v1"
    )
  end

  def raw_body=(value)
    self.raw_body_ciphertext = Payment::CredentialVault.encrypt(
      value.to_s,
      purpose: "crystell:payment-webhook-body:v1"
    )
  end
end
