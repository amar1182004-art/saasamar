class UsageTotal < ApplicationRecord
  belongs_to :tenant
  belongs_to :billing_feature

  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :period_start, :period_end, presence: true
  validate :period_is_valid

  private

  def period_is_valid
    return if period_start.blank? || period_end.blank?
    return if period_end > period_start

    errors.add(:period_end, "must be after period start")
  end
end
