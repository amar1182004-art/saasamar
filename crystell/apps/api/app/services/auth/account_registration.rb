require "uri"

module Auth
  class AccountRegistration
    class ValidationError < StandardError; end
    class ConflictError < StandardError; end

    Result = Data.define(:user_id, :tenant_id, :store_id)
    SLUG_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    def self.call(email:, password:, tenant_name:, tenant_slug:, store_name:, store_slug:)
      email = email.to_s.strip.downcase
      tenant_name = tenant_name.to_s.strip
      tenant_slug = tenant_slug.to_s.strip.downcase
      store_name = store_name.to_s.strip
      store_slug = store_slug.to_s.strip.downcase
      password = password.to_s

      validate!(
        email: email,
        password: password,
        tenant_name: tenant_name,
        tenant_slug: tenant_slug,
        store_name: store_name,
        store_slug: store_slug
      )

      digest = BCrypt::Password.create(password)
      connection = ActiveRecord::Base.connection
      row = connection.select_one(<<~SQL.squish)
        SELECT * FROM crystell.create_initial_account(
          #{connection.quote(email)},
          #{connection.quote(digest.to_s)},
          #{connection.quote(tenant_name)},
          #{connection.quote(tenant_slug)},
          #{connection.quote(store_name)},
          #{connection.quote(store_slug)}
        )
      SQL

      Result.new(
        user_id: row.fetch("user_id"),
        tenant_id: row.fetch("tenant_id"),
        store_id: row.fetch("store_id")
      )
    rescue ActiveRecord::StatementInvalid => error
      raise ConflictError, "account identifiers already exist" if unique_violation?(error)

      raise
    end

    def self.validate!(email:, password:, tenant_name:, tenant_slug:, store_name:, store_slug:)
      raise ValidationError, "invalid email" unless email.match?(URI::MailTo::EMAIL_REGEXP)
      raise ValidationError, "password must be between 12 and 72 bytes" unless password.bytesize.between?(12, 72)
      raise ValidationError, "tenant name is required" unless tenant_name.length.between?(2, 120)
      raise ValidationError, "store name is required" unless store_name.length.between?(2, 120)
      raise ValidationError, "invalid tenant slug" unless tenant_slug.match?(SLUG_PATTERN)
      raise ValidationError, "invalid store slug" unless store_slug.match?(SLUG_PATTERN)
    end
    private_class_method :validate!

    def self.unique_violation?(error)
      cause = error.cause
      defined?(PG::UniqueViolation) && cause.is_a?(PG::UniqueViolation)
    end
    private_class_method :unique_violation?
  end
end
