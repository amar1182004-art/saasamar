module V1
  module Security
    class SessionsController < ApplicationController
      include Authentication

      def index
        IdentityScope.with(Current.user.id) do
          sessions = Session.active.order(created_at: :desc).map do |session|
            {
              id: session.id,
              current: session.id == Current.session.id,
              user_agent: session.user_agent,
              ip_hash: session.ip_hash,
              created_at: session.created_at,
              expires_at: session.expires_at
            }
          end

          render json: { sessions: sessions }
        end
      end

      def destroy
        IdentityScope.with(Current.user.id) do
          session = Session.find_by(id: params[:id])
          return render json: { error: "session_not_found" }, status: :not_found unless session

          unless session.revoked_at
            session.update!(revoked_at: Time.current)
            SecurityAudit.record!(
              "auth.session_revoked",
              metadata: { session_id: session.id, current: session.id == Current.session.id }
            )
          end

          head :no_content
        end
      end

      def revoke_others
        IdentityScope.with(Current.user.id) do
          revoked_count = Session.active.where.not(id: Current.session.id).update_all(
            revoked_at: Time.current,
            updated_at: Time.current
          )

          SecurityAudit.record!(
            "auth.other_sessions_revoked",
            metadata: { revoked_count: revoked_count, current_session_id: Current.session.id }
          )
        end

        head :no_content
      end
    end
  end
end
