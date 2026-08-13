module Control
  module V1
    class ElevationsController < BaseController
      def create
        session = ControlPlane::PrivilegeElevator.call(
          password: params.require(:password),
          otp: params.require(:otp),
          ip_address: request.remote_ip
        )

        render json: {
          elevated: session.elevated?,
          privilege_elevated_until: session.privilege_elevated_until
        }
      rescue ControlPlane::Permission::ForbiddenError
        render json: { error: "control_plane_forbidden" }, status: :forbidden
      rescue ControlPlane::PrivilegeElevator::VerificationError, ActionController::ParameterMissing
        render json: { error: "control_plane_elevation_failed" }, status: :unauthorized
      end
    end
  end
end
