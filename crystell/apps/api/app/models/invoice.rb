class Invoice < ApplicationRecord
  belongs_to :tenant
  belongs_to :subscription, optional: true

  normalizes :currency, with: ->(currency) { currency.strip.upcase }

  validates :number, presence: true, uniqueness: { scope: :tenant_id }
  validates :status, inclusion: { in: %w[draft open paid void uncollectible] }
  validates :currency, presence: true, length: { is: 3 }
  validates :subtotal_cents, :discount_cents, :tax_cents, :total_cents, :amount_paid_cents,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }
end
