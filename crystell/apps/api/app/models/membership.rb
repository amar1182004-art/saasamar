class Membership < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  validates :role, inclusion: { in: %w[owner admin member] }
  validates :status, inclusion: { in: %w[active invited suspended] }
  validates :user_id, uniqueness: { scope: :tenant_id }
end
