module V1
  module Auth
    class RegistrationsController < ApplicationController
      def create
        registration = ::Auth::AccountRegistration.call(
          email: params[:email],
          password: params[:password],
          tenant_name: params[:tenant_name],
          tenant_slug: params[:tenant_slug],
          store_name: params[:store_name],
          store_slug: params[:store_slug]
        )

        issued = ::Auth::SessionIssuer.call(
          user_id: registration.user_id,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        render json: {
          token: issued.token,
          token_type: "Bearer",
          expires_at: issued.expires_at,
          user_id: registration.user_id,
          tenant_id: registration.tenant_id,
          store_id: registration.store_id
        }, status: :created
      rescue ::Auth::AccountRegistration::ValidationError => error
        render json: { error: "validation_error", message: error.message }, status: :unprocessable_entity
      rescue ::Auth::AccountRegistration::ConflictError
        render json: { error: "account_conflict" }, status: :conflict
      end
    end
  end
end
