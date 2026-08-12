module Auth
  class PasswordAuthenticator
    Result = Data.define(:user_id, :email, :mfa_enabled)
    DUMMY_DIGEST = BCrypt::Password.create("crystell-invalid-password").to_s.freeze

    def self.call(email:, password:)
      normalized_email = email.to_s.strip.downcase
      return nil if normalized_email.blank? || password.to_s.blank?

      connection = ActiveRecord::Base.connection
      row = connection.select_one(
        "SELECT * FROM crystell.user_for_password_auth(#{connection.quote(normalized_email)})"
      )

      digest = row&.fetch("password_digest", nil).presence || DUMMY_DIGEST
      valid_password = BCrypt::Password.new(digest).is_password?(password.to_s)

      return nil unless row && valid_password
      return nil unless row.fetch("status") == "active"

      Result.new(
        user_id: row.fetch("id"),
        email: row.fetch("email"),
        mfa_enabled: ActiveModel::Type::Boolean.new.cast(row.fetch("mfa_enabled"))
      )
    rescue BCrypt::Errors::InvalidHash
      nil
    end
  end
end
