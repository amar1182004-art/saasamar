class UsageEvent < ApplicationRecord
  belongs_to :tenant
  belongs_to :billing_feature

  validates :idempotency_key, presence: true, uniqueness: { scope: :tenant_id }
  validates :quantity, numericality: { greater_than: 0 }
  validates :occurred_at, presence: true

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
end
