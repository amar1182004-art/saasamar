class TenantAccess
  class ForbiddenError < StandardError; end

  def self.with(user:, tenant_id:)
    raise ForbiddenError, "tenant is required" if tenant_id.blank?

    previous_user = Current.user
    previous_tenant_id = Current.tenant_id

    ActiveRecord::Base.transaction(requires_new: true) do
      connection = ActiveRecord::Base.connection
      connection.execute(
        "SELECT set_config('app.current_user_id', #{connection.quote(user.id.to_s)}, true)"
      )
      connection.execute(
        "SELECT set_config('app.current_tenant_id', #{connection.quote(tenant_id.to_s)}, true)"
      )

      membership = Membership.find_by(user_id: user.id, status: "active")
      raise ForbiddenError, "tenant access denied" unless membership

      Current.user = user
      Current.tenant_id = tenant_id.to_s
      yield membership
    ensure
      Current.user = previous_user
      Current.tenant_id = previous_tenant_id
    end
  end
end
