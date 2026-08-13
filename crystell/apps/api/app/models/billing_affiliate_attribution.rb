class BillingAffiliateAttribution < ApplicationRecord
  belongs_to :tenant
  belongs_to :billing_affiliate_code
  belongs_to :converted_subscription, class_name: "Subscription", optional: true
  has_many :billing_commissions, dependent: :restrict_with_exception

  validates :status, inclusion: { in: %w[active converted expired void] }
  validates :attributed_at, presence: true

  scope :active, -> { where(status: "active") }
end
