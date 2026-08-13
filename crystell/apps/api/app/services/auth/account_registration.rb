require "uri"

module Auth
  class AccountRegistration
    class ValidationError < StandardError; end
    class ConflictError < StandardError; end
    class DeliveryError < StandardError; end

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

      password_digest = BCrypt::Password.create(password).to_s
      connection = ActiveRecord::Base.connection
      binds = [
        query_attribute("email", email),
        query_attribute("password_digest", password_digest),
        query_attribute("tenant_name", tenant_name),
        query_attribute("tenant_slug", tenant_slug),
        query_attribute("store_name", store_name),
        query_attribute("store_slug", store_slug)
      ]

      row = ActiveRecord::Base.transaction do
        created = connection.exec_query(
          <<~SQL.squish,
            SELECT * FROM crystell.create_initial_account($1, $2, $3, $4, $5, $6)
          SQL
          "CreateInitialAccount",
          binds
        ).first

        verification = IdentityDelivery.request(
          email: email,
          purpose: "email_verification"
        )
        raise DeliveryError, "unable to queue email verification" unless verification.queued

        created
      end

      Result.new(
        user_id: row.fetch("user_id"),
        tenant_id: row.fetch("tenant_id"),
        store_id: row.fetch("store_id")
      )
    rescue ActiveRecord::StatementInvalid => error
      raise ConflictError, "account identifiers already exist" if unique_violation?(error)

      raise
    end

    def self.query_attribute(name, value)
      ActiveRecord::Relation::QueryAttribute.new(
        name,
        value,
        ActiveRecord::Type::String.new
      )
    end
    private_class_method :query_attribute

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
