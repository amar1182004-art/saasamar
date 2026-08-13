class BillingEvent < ApplicationRecord
  belongs_to :tenant
  belongs_to :actor_user, class_name: "User", optional: true

  attribute :occurred_at, :datetime, default: -> { Time.current }

  validates :event_type, presence: true
  validates :occurred_at, presence: true

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
end
