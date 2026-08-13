class BillingCoupon < ApplicationRecord
  belongs_to :billing_plan, optional: true
  has_many :billing_coupon_redemptions, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :discount_type, inclusion: { in: %w[percentage fixed] }
  validates :status, inclusion: { in: %w[active disabled expired] }
  validates :per_tenant_limit, numericality: { only_integer: true, greater_than: 0 }
  validate :discount_value_is_valid
  validate :window_is_valid

  def active_at?(time = Time.current)
    status == "active" && (starts_at.nil? || starts_at <= time) && (ends_at.nil? || ends_at > time)
  end

  private

  def discount_value_is_valid
    if discount_type == "percentage"
      errors.add(:percentage_basis_points, "must be between 1 and 10000") unless percentage_basis_points.to_i.between?(1, 10_000)
    elsif discount_type == "fixed"
      errors.add(:fixed_amount_cents, "must be positive") unless fixed_amount_cents.to_i.positive?
      errors.add(:currency, "is required") if currency.blank?
    end
  end

  def window_is_valid
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after starts_at")
  end
end
