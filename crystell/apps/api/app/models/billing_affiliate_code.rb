class BillingAffiliateCode < ApplicationRecord
  belongs_to :billing_affiliate
  has_many :billing_affiliate_attributions, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: %w[active disabled expired] }
  validate :window_is_valid

  def active_at?(time = Time.current)
    status == "active" && billing_affiliate.status == "active" &&
      (starts_at.nil? || starts_at <= time) && (ends_at.nil? || ends_at > time)
  end

  private

  def window_is_valid
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts_at")
  end
end
