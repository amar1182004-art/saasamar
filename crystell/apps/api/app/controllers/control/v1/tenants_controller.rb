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

      def show
        row = ControlPlane::TenantSupportOverview.call(
          tenant_id: params.require(:id),
          request_id: request.request_id,
          ip_address: request.remote_ip
        )

        render json: { tenant: serialize_support_overview(row) }
      rescue ControlPlane::Permission::ForbiddenError
        render json: { error: "control_plane_forbidden" }, status: :forbidden
      rescue ControlPlane::TenantSupportOverview::NotFoundError
        render json: { error: "tenant_not_found" }, status: :not_found
      rescue ActiveRecord::StatementInvalid => error
        raise unless error.cause.is_a?(PG::InvalidTextRepresentation)

        render json: { error: "tenant_not_found" }, status: :not_found
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

      def serialize_support_overview(row)
        {
          id: row.fetch("tenant_id"),
          name: row.fetch("tenant_name"),
          slug: row.fetch("tenant_slug"),
          status: row.fetch("tenant_status"),
          stores: {
            total: row.fetch("stores_count").to_i,
            active: row.fetch("active_stores_count").to_i
          },
          commerce: {
            orders: row.fetch("orders_count").to_i,
            paid_orders: row.fetch("paid_orders_count").to_i,
            open_shipments: row.fetch("open_shipments_count").to_i,
            products: row.fetch("products_count").to_i,
            active_products: row.fetch("active_products_count").to_i
          },
          subscription: {
            status: row["subscription_status"],
            plan_code: row["subscription_plan_code"]
          },
          created_at: row.fetch("created_at")
        }
      end
    end
  end
end
