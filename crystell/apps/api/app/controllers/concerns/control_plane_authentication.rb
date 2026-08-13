module ControlPlaneAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_control_plane!
    after_action :reset_control_plane_context
  end

  private

  def authenticate_control_plane!
    ControlPlane::SessionAuthenticator.call(token: control_plane_bearer_token)
  rescue ControlPlane::SessionAuthenticator::UnauthorizedError
    render json: { error: "control_plane_unauthorized" }, status: :unauthorized
  end

  def control_plane_bearer_token
    scheme, token = request.authorization.to_s.split(" ", 2)
    return "" unless scheme&.casecmp("Bearer")&.zero? && token.present?

    token
  end

  def reset_control_plane_context
    ControlPlaneCurrent.reset
  end
end
