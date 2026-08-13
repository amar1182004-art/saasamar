module V1
  class DashboardController < ApplicationController
    include Authentication
    include TenantAuthorization

    def show
      render json: { dashboard: Dashboard::Summary.call(store_id: params.require(:store_id)) }
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    rescue ActiveRecord::RecordNotFound
      render json: { error: "store_not_found" }, status: :not_found
    end
  end
end
