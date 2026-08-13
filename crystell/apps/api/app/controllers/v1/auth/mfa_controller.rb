module V1
  module Auth
    class MfaController < ApplicationController
      include Authentication
      skip_before_action :authenticate_request!, only: :challenge

      def setup
        setup = ::Auth::MfaEnrollment.begin_for(Current.user)
        render json: {
          secret: setup.secret,
          provisioning_uri: setup.provisioning_uri
        }, status: :created
      rescue ::Auth::MfaEnrollment::AlreadyEnabledError
        render json: { error: "mfa_already_enabled" }, status: :conflict
      end

      def confirm
        confirmation = ::Auth::MfaEnrollment.confirm!(
          user: Current.user,
          code: params[:code]
        )
        render json: { recovery_codes: confirmation.recovery_codes }, status: :ok
      rescue ::Auth::MfaEnrollment::AlreadyEnabledError
        render json: { error: "mfa_already_enabled" }, status: :conflict
      rescue ::Auth::MfaEnrollment::InvalidCodeError
        render json: { error: "invalid_mfa_code" }, status: :unprocessable_entity
      end

      def challenge
        verified = ::Auth::MfaVerifier.verify!(
          challenge_token: params[:challenge_token],
          code: params[:code],
          recovery_code: params[:recovery_code]
        )

        issued = ::Auth::SessionIssuer.call(
          user_id: verified.user_id,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        render json: {
          token: issued.token,
          token_type: "Bearer",
          expires_at: issued.expires_at
        }, status: :created
      rescue ::Auth::MfaVerifier::InvalidChallengeError
        render json: { error: "invalid_mfa_challenge" }, status: :unauthorized
      rescue ::Auth::MfaVerifier::InvalidCodeError
        render json: { error: "invalid_mfa_code" }, status: :unauthorized
      end

      def regenerate_recovery_codes
        codes = ::Auth::MfaManagement.regenerate_recovery_codes!(
          user: Current.user,
          current_session_id: Current.session.id,
          password: params[:password],
          code: params[:code],
          recovery_code: params[:recovery_code]
        )

        render json: { recovery_codes: codes }, status: :ok
      rescue ::Auth::SensitiveReauthentication::FailedError
        render json: { error: "reauthentication_failed" }, status: :unauthorized
      rescue ::Auth::MfaManagement::NotEnabledError
        render json: { error: "mfa_not_enabled" }, status: :conflict
      end

      def destroy
        ::Auth::MfaManagement.disable!(
          user: Current.user,
          current_session_id: Current.session.id,
          password: params[:password],
          code: params[:code],
          recovery_code: params[:recovery_code]
        )

        head :no_content
      rescue ::Auth::SensitiveReauthentication::FailedError
        render json: { error: "reauthentication_failed" }, status: :unauthorized
      rescue ::Auth::MfaManagement::NotEnabledError
        render json: { error: "mfa_not_enabled" }, status: :conflict
      end
    end
  end
end
