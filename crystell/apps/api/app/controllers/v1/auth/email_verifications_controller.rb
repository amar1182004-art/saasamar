module V1
  module Auth
    class EmailVerificationsController < ApplicationController
      include Authentication
      skip_before_action :authenticate_request!, only: :update

      def create
        email = Current.user.email
        throttle = ::Auth::IdentityRequestThrottle.new(
          email: email,
          ip_address: request.remote_ip,
          purpose: "email_verification"
        )

        if throttle.blocked?
          response.set_header("Retry-After", throttle.retry_after.to_s)
          return render json: { error: "too_many_requests" }, status: :too_many_requests
        end

        throttle.record!
        ::Auth::IdentityDelivery.request(email: email, purpose: "email_verification") unless Current.user.email_verified_at
        head :accepted
      end

      def update
        consumed = ::Auth::IdentityTokenConsumer.verify_email!(params[:token])
        return head :no_content if consumed

        render json: { error: "invalid_or_expired_token" }, status: :unprocessable_entity
      end
    end
  end
end
