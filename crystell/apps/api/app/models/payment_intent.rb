class PaymentIntent < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :order
  belongs_to :checkout_session
  belongs_to :payment_provider_account
  has_many :payment_transactions, dependent: :restrict_with_exception

  validates :status, inclusion: { in: %w[created pending requires_action authorized paid failed cancelled] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :idempotency_key, presence: true

  scope :open, -> { where(status: %w[created pending requires_action authorized]) }
end
