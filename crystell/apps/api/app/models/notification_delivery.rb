class NotificationDelivery < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :notification_template
  belongs_to :communication_provider_account
  belongs_to :user, optional: true

  validates :channel, inclusion: { in: %w[email sms whatsapp] }
  validates :recipient_ciphertext, :destination_fingerprint, :payload_ciphertext, :idempotency_key, presence: true
  validates :status, inclusion: { in: %w[queued sending sent failed] }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
