require "digest"
require "securerandom"

module Auth
  class IdentityDelivery
    Result = Data.define(:queued, :token, :expires_at)

    PURPOSE_TTL = {
      "email_verification" => -> { ENV.fetch("EMAIL_VERIFICATION_TTL_HOURS", "24").to_i.hours },
      "password_reset" => -> { ENV.fetch("PASSWORD_RESET_TTL_MINUTES", "60").to_i.minutes }
    }.freeze

    def self.request(email:, purpose:)
      normalized_email = email.to_s.strip.downcase
      ttl = PURPOSE_TTL.fetch(purpose.to_s) { raise ArgumentError, "invalid identity delivery purpose" }.call
      token = SecureRandom.urlsafe_base64(48)
      token_digest = Digest::SHA256.hexdigest(token)
      expires_at = ttl.from_now
      destination_fingerprint = DeliveryFingerprint.call(normalized_email)
      encrypted_payload = IdentityDeliveryCipher.encrypt(
        "email" => normalized_email,
        "purpose" => purpose.to_s,
        "token" => token,
        "expires_at" => expires_at.iso8601
      )

      connection = ActiveRecord::Base.connection
      binds = [
        string_attribute("email", normalized_email),
        string_attribute("purpose", purpose.to_s),
        string_attribute("token_digest", token_digest),
        string_attribute("expires_at", expires_at.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")),
        string_attribute("destination_fingerprint", destination_fingerprint),
        string_attribute("encrypted_payload", encrypted_payload)
      ]

      row = connection.exec_query(
        <<~SQL.squish,
          SELECT crystell.request_identity_delivery(
            $1::text,
            $2::text,
            $3::text,
            CAST($4 AS timestamp without time zone),
            $5::text,
            $6::text
          ) AS queued
        SQL
        "RequestIdentityDelivery",
        binds
      ).first

      queued = ActiveModel::Type::Boolean.new.cast(row&.fetch("queued", false))
      Result.new(queued: queued, token: queued ? token : nil, expires_at: queued ? expires_at : nil)
    end

    def self.string_attribute(name, value)
      ActiveRecord::Relation::QueryAttribute.new(name, value, ActiveRecord::Type::String.new)
    end
    private_class_method :string_attribute
  end
end
