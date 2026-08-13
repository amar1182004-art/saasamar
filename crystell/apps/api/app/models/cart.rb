class Cart < ApplicationRecord
  belongs_to :tenant
  belongs_to :store
  has_many :cart_items, dependent: :delete_all
  has_many :checkout_sessions

  validates :access_token_digest, presence: true
  validates :status, inclusion: { in: %w[active checking_out converted abandoned expired] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }, allow_nil: true
  validates :expires_at, presence: true

  def expired?
    expires_at <= Time.current
  end
end
