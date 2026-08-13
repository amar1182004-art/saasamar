require "digest"

module ControlPlane
  class SessionAuthenticator
    class UnauthorizedError < StandardError; end

    Result = Data.define(:user, :session)

    def self.call(token:, now: Time.current)
      digest = Digest::SHA256.hexdigest(token.to_s)
      session = ControlPlaneSession.active.includes(:control_plane_user).find_by(token_digest: digest)
      user = session&.control_plane_user

      unless session&.active? && user&.status == "active"
        raise UnauthorizedError, "control plane session is invalid"
      end

      if session.last_seen_at.blank? || session.last_seen_at < now - 5.minutes
        session.update!(last_seen_at: now)
      end

      ControlPlaneCurrent.user = user
      ControlPlaneCurrent.session = session
      Result.new(user: user, session: session)
    end
  end
end
