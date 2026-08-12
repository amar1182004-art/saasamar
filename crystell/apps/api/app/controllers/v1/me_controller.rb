module V1
  class MeController < ApplicationController
    include Authentication

    def show
      IdentityScope.with(Current.user.id) do
        user = User.find(Current.user.id)
        render json: {
          id: user.id,
          email: user.email,
          status: user.status,
          mfa_enabled: user.mfa_enabled,
          last_signed_in_at: user.last_signed_in_at
        }
      end
    end
  end
end
