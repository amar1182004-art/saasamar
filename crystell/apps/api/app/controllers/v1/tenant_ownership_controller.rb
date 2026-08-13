module V1
  class TenantOwnershipController < ApplicationController
    include Authentication
    include TenantAuthorization

    def transfer
      result = TenantOwnershipTransfer.call(
        target_membership_id: params[:target_membership_id]
      )

      render json: { target_user_id: result.target_user_id }, status: :ok
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    rescue TenantOwnershipTransfer::InvalidTargetError
      render json: { error: "invalid_ownership_target" }, status: :unprocessable_entity
    end
  end
end
