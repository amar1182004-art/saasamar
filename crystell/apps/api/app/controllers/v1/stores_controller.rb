module V1
  class StoresController < ApplicationController
    include Authentication
    include TenantAuthorization

    def index
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
    end
  end
end
