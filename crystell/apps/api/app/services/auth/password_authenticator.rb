module Auth
  class PasswordAuthenticator
    Result = Data.define(:user_id, :email, :mfa_enabled, :locked_until)
    DUMMY_DIGEST = BCrypt::Password.create("crystell-invalid-password").to_s.freeze

    def self.call(email:, password:)
      normalized_email = email.to_s.strip.downcase
      return nil if normalized_email.blank? || password.to_s.blank?

      connection = ActiveRecord::Base.connection
      row = connection.exec_query(
        "SELECT * FROM crystell.user_for_password_auth($1)",
        "PasswordAuthLookup",
        [query_attribute("email", normalized_email)]
      ).first

      digest = row&.fetch("password_digest", nil).presence || DUMMY_DIGEST
      valid_password = BCrypt::Password.new(digest).is_password?(password.to_s)

      return nil unless row && valid_password
      return nil unless row.fetch("status") == "active"

      Result.new(
        user_id: row.fetch("id"),
        email: row.fetch("email"),
        mfa_enabled: ActiveModel::Type::Boolean.new.cast(row.fetch("mfa_enabled")),
        locked_until: parse_time(row.fetch("locked_until", nil))
      )
    rescue BCrypt::Errors::InvalidHash
      nil
    end

    def self.query_attribute(name, value)
      ActiveRecord::Relation::QueryAttribute.new(name, value, ActiveRecord::Type::String.new)
    end
    private_class_method :query_attribute

    def self.parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    end
    private_class_method :parse_time
  end
end
