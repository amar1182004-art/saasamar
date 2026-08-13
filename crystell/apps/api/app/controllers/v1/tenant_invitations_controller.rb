module V1
  class TenantInvitationsController < ApplicationController
    include Authentication
    include TenantAuthorization

    def index
      TenantPermission.require!(Current.membership, "members.read")

      invitations = TenantInvitation.order(created_at: :desc).map do |invitation|
        {
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          expires_at: invitation.expires_at,
          accepted_at: invitation.accepted_at,
          revoked_at: invitation.revoked_at,
          created_at: invitation.created_at
        }
      end

      render json: { invitations: invitations }
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    end

    def create
      TenantPermission.require!(Current.membership, "members.invite")

      invitation = ::Auth::TenantInvitationIssuer.call(
        email: params[:email],
        role: params[:role]
      )

      render json: {
        invitation: {
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          expires_at: invitation.expires_at
        }
      }, status: :created
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    rescue ::Auth::TenantInvitationIssuer::ValidationError => error
      render json: { error: "validation_error", message: error.message }, status: :unprocessable_entity
    rescue ::Auth::TenantInvitationIssuer::ConflictError
      render json: { error: "invitation_conflict" }, status: :conflict
    end

    def destroy
      TenantPermission.require!(Current.membership, "members.invite")

      invitation = TenantInvitation.find_by(id: params[:id])
      return render json: { error: "invitation_not_found" }, status: :not_found unless invitation

      if invitation.accepted_at
        return render json: { error: "invitation_already_accepted" }, status: :conflict
      end

      unless invitation.revoked_at
        invitation.update!(revoked_at: Time.current)
        SecurityAudit.record!(
          "tenant.invitation_revoked",
          metadata: { invitation_id: invitation.id }
        )
      end

      head :no_content
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    end
  end
end
