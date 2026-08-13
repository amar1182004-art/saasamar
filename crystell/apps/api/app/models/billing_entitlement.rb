class BillingEntitlement < ApplicationRecord
  belongs_to :billing_plan
  belongs_to :billing_feature

  validates :value, presence: true
  validates :billing_feature_id, uniqueness: { scope: :billing_plan_id }
end
