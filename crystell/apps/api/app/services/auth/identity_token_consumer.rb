require "digest"

module Auth
  class IdentityTokenConsumer
    class InvalidPasswordError < StandardError; end

    def self.verify_email!(token)
      digest = token_digest(token)
      return false unless digest

      call_boolean_function(
        "SELECT crystell.consume_email_verification($1::text) AS consumed",
        "ConsumeEmailVerification",
        [string_attribute("token_digest", digest)]
      )
    end

    def self.reset_password!(token:, password:)
      password = password.to_s
      unless password.bytesize.between?(12, 72)
        raise InvalidPasswordError, "password must be between 12 and 72 bytes"
      end

      digest = token_digest(token)
      return false unless digest

      password_digest = BCrypt::Password.create(password).to_s
      call_boolean_function(
        "SELECT crystell.consume_password_reset($1::text, $2::text) AS consumed",
        "ConsumePasswordReset",
        [
          string_attribute("token_digest", digest),
          string_attribute("password_digest", password_digest)
        ]
      )
    end

    def self.token_digest(token)
      value = token.to_s
      return if value.blank? || value.bytesize > 512

      Digest::SHA256.hexdigest(value)
    end
    private_class_method :token_digest

    def self.call_boolean_function(sql, name, binds)
      row = ActiveRecord::Base.connection.exec_query(sql, name, binds).first
      ActiveModel::Type::Boolean.new.cast(row&.fetch("consumed", false))
    end
    private_class_method :call_boolean_function

    def self.string_attribute(name, value)
      ActiveRecord::Relation::QueryAttribute.new(name, value, ActiveRecord::Type::String.new)
    end
    private_class_method :string_attribute
  end
end
