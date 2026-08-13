module Control
  module V1
    class SecurityController < BaseController
      def show
        overview = ControlPlane::SecurityOverview.call(
          request_id: request.request_id,
          ip_address: request.remote_ip
        )

        render json: { security: overview }
      rescue ControlPlane::Permission::ForbiddenError
        render json: { error: "control_plane_forbidden" }, status: :forbidden
      end
    end
  end
end
