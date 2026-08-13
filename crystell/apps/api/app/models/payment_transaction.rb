class PaymentTransaction < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :payment_intent

  validates :kind, inclusion: { in: %w[authorization capture refund void failure] }
  validates :status, inclusion: { in: %w[pending succeeded failed] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :idempotency_key, presence: true
end
