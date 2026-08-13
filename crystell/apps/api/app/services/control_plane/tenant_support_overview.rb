module ControlPlane
  class TenantSupportOverview
    class NotFoundError < StandardError; end

    def self.call(tenant_id:, request_id: nil, ip_address: nil)
      user = ControlPlaneCurrent.user
      Permission.require!(user, "tenant.support")

      connection = ControlPlaneRecord.connection
      row = connection.select_one(<<~SQL)
        SELECT *
        FROM control_plane_api.tenant_support_overview(
          #{connection.quote(tenant_id)}::uuid
        )
      SQL
      raise NotFoundError, "tenant not found" if row.blank?

      AuditWriter.call(
        action: "control_plane.tenant_support_overview_viewed",
        target_type: "Tenant",
        target_id: row.fetch("tenant_id"),
        request_id: request_id,
        ip_address: ip_address,
        metadata: {
          "stores_count" => row.fetch("stores_count").to_i,
          "orders_count" => row.fetch("orders_count").to_i,
          "open_shipments_count" => row.fetch("open_shipments_count").to_i
        }
      )

      row
    end
  end
end
