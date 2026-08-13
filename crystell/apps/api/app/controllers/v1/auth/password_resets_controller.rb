module V1
  module Auth
    class PasswordResetsController < ApplicationController
      def create
        email = params[:email].to_s.strip.downcase
        throttle = ::Auth::IdentityRequestThrottle.new(
          email: email,
          ip_address: request.remote_ip,
          purpose: "password_reset"
        )

        if throttle.blocked?
          response.set_header("Retry-After", throttle.retry_after.to_s)
          return render json: { error: "too_many_requests" }, status: :too_many_requests
        end

        throttle.record!
        ::Auth::IdentityDelivery.request(email: email, purpose: "password_reset")
        head :accepted
      end

      def update
        consumed = ::Auth::IdentityTokenConsumer.reset_password!(
          token: params[:token],
          password: params[:password]
        )

        return head :no_content if consumed

        render json: { error: "invalid_or_expired_token" }, status: :unprocessable_entity
      rescue ::Auth::IdentityTokenConsumer::InvalidPasswordError => error
        render json: { error: "validation_error", message: error.message }, status: :unprocessable_entity
      end
    end
  end
end
