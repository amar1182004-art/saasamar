class MerchantTenantDirectory
  Result = Data.define(
    :tenant_id,
    :tenant_name,
    :tenant_slug,
    :tenant_status,
    :membership_role,
    :membership_status,
    :stores_count
  )

  def self.call(user: Current.user)
    raise ArgumentError, "authenticated user is required" unless user

    IdentityScope.with(user.id) do
      sql = "SELECT * FROM crystell.current_user_tenants()"
      ApplicationRecord.connection.exec_query(sql).map do |row|
        Result.new(
          tenant_id: row.fetch("tenant_id"),
          tenant_name: row.fetch("tenant_name"),
          tenant_slug: row.fetch("tenant_slug"),
          tenant_status: row.fetch("tenant_status"),
          membership_role: row.fetch("membership_role"),
          membership_status: row.fetch("membership_status"),
          stores_count: row.fetch("stores_count").to_i
        )
      end
    end
  end
end
