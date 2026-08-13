module V1
  class TenantsController < ApplicationController
    include Authentication

    def index
      tenants = MerchantTenantDirectory.call

      render json: {
        tenants: tenants.map do |tenant|
          {
            id: tenant.tenant_id,
            name: tenant.tenant_name,
            slug: tenant.tenant_slug,
            status: tenant.tenant_status,
            membership: {
              role: tenant.membership_role,
              status: tenant.membership_status
            },
            stores_count: tenant.stores_count,
            accessible: tenant.tenant_status == "active" && tenant.membership_status == "active"
          }
        end
      }
    end
  end
end
