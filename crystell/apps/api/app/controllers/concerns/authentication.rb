module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request!
  end

  private

  def authenticate_request!
    result = Auth::SessionAuthenticator.call(bearer_token)
    return render json: { error: "unauthorized" }, status: :unauthorized unless result

    Current.user = result.user
    Current.session = result.session
  end

  def bearer_token
    scheme, token = request.authorization.to_s.split(" ", 2)
    return unless scheme&.casecmp("Bearer")&.zero?

    token
  end
end
