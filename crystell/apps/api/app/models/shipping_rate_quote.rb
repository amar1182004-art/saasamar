class ShippingRateQuote < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  belongs_to :checkout_session
  belongs_to :shipping_provider_account

  validates :service_code, :service_name, :request_digest, presence: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true

  def expired?
    expires_at <= Time.current
  end
end
