module Control
  module V1
    class MeController < BaseController
      def show
        user = ControlPlaneCurrent.user
        session = ControlPlaneCurrent.session

        render json: {
          user: {
            id: user.id,
            email: user.email,
            role: user.role
          },
          session: {
            id: session.id,
            expires_at: session.expires_at,
            elevated: session.elevated?,
            privilege_elevated_until: session.privilege_elevated_until
          }
        }
      end
    end
  end
end
