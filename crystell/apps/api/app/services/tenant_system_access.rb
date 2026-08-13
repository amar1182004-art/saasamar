class TenantSystemAccess
  class ForbiddenError < StandardError; end

  def self.with(tenant_id:)
    raise ForbiddenError, "tenant is required" if tenant_id.blank?

    previous_user = Current.user
    previous_tenant_id = Current.tenant_id
    previous_membership = Current.membership

    ActiveRecord::Base.transaction(requires_new: true) do
      connection = ActiveRecord::Base.connection
      connection.execute("SELECT set_config('app.current_user_id', '', true)")
      connection.execute(
        "SELECT set_config('app.current_tenant_id', #{connection.quote(tenant_id.to_s)}, true)"
      )

      tenant = Tenant.find_by(id: tenant_id)
      raise ForbiddenError, "tenant does not exist" unless tenant

      Current.user = nil
      Current.tenant_id = tenant.id.to_s
      Current.membership = nil

      yield tenant
    ensure
      Current.user = previous_user
      Current.tenant_id = previous_tenant_id
      Current.membership = previous_membership
    end
  end
end
