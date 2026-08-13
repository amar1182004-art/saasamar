class TenantScope
  class MissingTenantError < StandardError; end

  def self.with(tenant_id)
    raise MissingTenantError, "tenant_id is required" if tenant_id.blank?

    previous_tenant_id = Current.tenant_id

    ActiveRecord::Base.transaction(requires_new: true) do
      connection = ActiveRecord::Base.connection
      connection.execute(
        "SELECT set_config('app.current_tenant_id', #{connection.quote(tenant_id.to_s)}, true)"
      )
      Current.tenant_id = tenant_id.to_s
      yield
    ensure
      Current.tenant_id = previous_tenant_id
    end
  end
end
