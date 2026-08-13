class Current < ActiveSupport::CurrentAttributes
  attribute :user, :session, :tenant_id, :membership
end
