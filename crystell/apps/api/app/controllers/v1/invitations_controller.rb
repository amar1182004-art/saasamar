module V1
  class InvitationsController < ApplicationController
    include Authentication

    def accept
      result = ::Auth::TenantInvitationAcceptor.call(
        user: Current.user,
        token: params[:token]
      )

      render json: { tenant_id: result.tenant_id }, status: :ok
    rescue ::Auth::TenantInvitationAcceptor::InvalidInvitationError
      render json: { error: "invalid_or_expired_invitation" }, status: :unprocessable_entity
    end
  end
end
