module V1
  class StoresController < ApplicationController
    include Authentication
    include TenantAuthorization

    def index
      TenantPermission.require!(Current.membership, "stores.read")

      render json: {
        tenant_id: Current.tenant_id,
        role: Current.membership.role,
        stores: Store.order(:created_at).map do |store|
          {
            id: store.id,
            name: store.name,
            slug: store.slug,
            status: store.status
          }
        end
      }
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    end
  end
end
