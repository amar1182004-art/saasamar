require "digest"

module Auth
  class SessionAuthenticator
    Result = Data.define(:user, :session)

    def self.call(token)
      return if token.blank?

      digest = Digest::SHA256.hexdigest(token.to_s)
      connection = ActiveRecord::Base.connection
      row = connection.select_one(
        "SELECT * FROM crystell.active_session_by_digest(#{connection.quote(digest)})"
      )
      return unless row

      IdentityScope.with(row.fetch("user_id")) do
        user = User.find_by(id: row.fetch("user_id"), status: "active")
        session = Session.find_by(id: row.fetch("session_id"))
        return unless user && session&.active?

        Result.new(user: user, session: session)
      end
    end
  end
end
