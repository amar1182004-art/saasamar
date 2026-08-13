class Subscription < ApplicationRecord
  belongs_to :tenant
  belongs_to :billing_plan
  belongs_to :billing_price
  has_many :invoices, dependent: :nullify

  normalizes :currency, with: ->(currency) { currency.strip.upcase }

  validates :status, inclusion: { in: %w[trialing active past_due paused canceled expired] }
  validates :currency, presence: true, length: { is: 3 }
  validates :interval, inclusion: { in: %w[monthly annual] }
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :period_is_valid

  scope :current, -> { where(status: %w[trialing active past_due paused]) }

  private

  def period_is_valid
    return if current_period_start.blank? || current_period_end.blank?
    return if current_period_end > current_period_start

    errors.add(:current_period_end, "must be after current period start")
  end
end
