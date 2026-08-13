module Control
  module V1
    class TenantsController < BaseController
      def index
        rows = ControlPlane::TenantDirectory.call(
          query: params[:q],
          limit: params[:limit],
          offset: params[:offset],
          request_id: request.request_id,
          ip_address: request.remote_ip
        )

        render json: {
          tenants: rows.map { |row| serialize_tenant(row) }
        }
      rescue ControlPlane::Permission::ForbiddenError
        render json: { error: "control_plane_forbidden" }, status: :forbidden
      end

      private

      def serialize_tenant(row)
        {
          id: row.fetch("tenant_id"),
          name: row.fetch("tenant_name"),
          slug: row.fetch("tenant_slug"),
          status: row.fetch("tenant_status"),
          stores_count: row.fetch("stores_count").to_i,
          active_stores_count: row.fetch("active_stores_count").to_i,
          created_at: row.fetch("created_at")
        }
      end
    end
  end
end
