module Control
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_control_plane!, only: :create

      def create
        result = ControlPlane::Authenticator.call(
          email: params.require(:email),
          password: params.require(:password),
          otp: params.require(:otp),
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        render json: {
          token: result.token,
          session: {
            id: result.session.id,
            expires_at: result.session.expires_at
          },
          user: {
            id: result.user.id,
            email: result.user.email,
            role: result.user.role
          }
        }, status: :created
      rescue ControlPlane::Authenticator::AuthenticationError, ActionController::ParameterMissing
        render json: { error: "control_plane_authentication_failed" }, status: :unauthorized
      ensure
        ControlPlaneCurrent.reset
      end

      def destroy
        session = ControlPlaneCurrent.session
        session.update!(revoked_at: Time.current, privilege_elevated_until: nil)
        ControlPlane::AuditWriter.call(
          action: "control_plane.session_revoked",
          target_type: "ControlPlaneSession",
          target_id: session.id,
          ip_address: request.remote_ip,
          reason: "logout"
        )
        head :no_content
      end
    end
  end
end
