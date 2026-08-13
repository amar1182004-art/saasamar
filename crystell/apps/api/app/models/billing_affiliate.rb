class BillingAffiliate < ApplicationRecord
  has_many :billing_affiliate_codes, dependent: :destroy
  has_many :billing_commissions, dependent: :restrict_with_exception

  validates :display_name, presence: true
  validates :status, inclusion: { in: %w[active paused closed] }
  validates :commission_type, inclusion: { in: %w[percentage fixed] }
  validate :commission_value_is_valid

  private

  def commission_value_is_valid
    if commission_type == "percentage"
      errors.add(:percentage_basis_points, "must be between 1 and 10000") unless percentage_basis_points.to_i.between?(1, 10_000)
    elsif commission_type == "fixed"
      errors.add(:fixed_amount_cents, "must be positive") unless fixed_amount_cents.to_i.positive?
      errors.add(:currency, "is required") if currency.blank?
    end
  end
end
