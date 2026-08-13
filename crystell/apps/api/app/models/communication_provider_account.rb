class CommunicationProviderAccount < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  has_many :notification_deliveries, dependent: :restrict_with_exception

  normalizes :channel, with: ->(value) { value.strip.downcase }
  normalizes :provider_key, with: ->(value) { value.strip.downcase }

  validates :channel, inclusion: { in: %w[email sms whatsapp] }
  validates :provider_key, format: { with: /\A[a-z0-9][a-z0-9_.-]{1,63}\z/ }
  validates :mode, inclusion: { in: %w[test live] }
  validates :status, inclusion: { in: %w[active disabled] }
  validates :credentials_ciphertext, presence: true
end
