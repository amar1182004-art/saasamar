module V1
  module Auth
    class SessionsController < ApplicationController
      include Authentication
      skip_before_action :authenticate_request!, only: :create

      def create
        throttle = ::Auth::LoginThrottle.new(
          email: params[:email],
          ip_address: request.remote_ip
        )

        if throttle.blocked?
          response.set_header("Retry-After", throttle.retry_after.to_s)
          return render json: { error: "too_many_attempts" }, status: :too_many_requests
        end

        result = ::Auth::PasswordAuthenticator.call(
          email: params[:email],
          password: params[:password]
        )

        unless result
          throttle.record_failure!
          return render json: { error: "invalid_credentials" }, status: :unauthorized
        end

        throttle.reset_success!

        if result.mfa_enabled
          challenge = ::Auth::MfaChallenge.issue(user_id: result.user_id)
          return render json: {
            error: "mfa_required",
            challenge_token: challenge.token,
            expires_in: challenge.expires_in
          }, status: :precondition_required
        end

        issued = ::Auth::SessionIssuer.call(
          user_id: result.user_id,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        render json: {
          token: issued.token,
          token_type: "Bearer",
          expires_at: issued.expires_at,
          user: { id: result.user_id, email: result.email }
        }, status: :created
      end

      def destroy
        IdentityScope.with(Current.user.id) do
          unless Current.session.revoked_at
            Current.session.update!(revoked_at: Time.current)
            SecurityAudit.record!(
              "auth.session_revoked",
              metadata: { session_id: Current.session.id, reason: "logout" }
            )
          end
        end
        head :no_content
      end
    end
  end
end
