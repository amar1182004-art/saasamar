class BillingEvent < ApplicationRecord
  belongs_to :tenant
  belongs_to :actor_user, class_name: "User", optional: true

  validates :event_type, presence: true
  validates :occurred_at, presence: true

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
end
