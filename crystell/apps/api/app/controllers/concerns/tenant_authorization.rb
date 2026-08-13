module TenantAuthorization
  extend ActiveSupport::Concern

  included do
    around_action :with_authorized_tenant
  end

  private

  def with_authorized_tenant
    tenant_id = request.headers[ENV.fetch("TENANT_CONTEXT_HEADER", "X-Crystell-Tenant")]

    TenantAccess.with(user: Current.user, tenant_id: tenant_id) do
      yield
    end
  rescue TenantAccess::ForbiddenError
    render json: { error: "tenant_forbidden" }, status: :forbidden
  end
end
