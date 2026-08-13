require "digest"
require "securerandom"
require "uri"

module Auth
  class TenantInvitationIssuer
    class ValidationError < StandardError; end
    class ConflictError < StandardError; end

    Result = Data.define(:id, :email, :role, :expires_at, :token)
    ALLOWED_ROLES = %w[admin member].freeze

    def self.call(email:, role:)
      raise ValidationError, "tenant context is required" if Current.tenant_id.blank?
      raise ValidationError, "authenticated user is required" unless Current.user

      email = email.to_s.strip.downcase
      role = role.to_s
      validate!(email:, role:)

      if ActiveSupport::SecurityUtils.secure_compare(email, Current.user.email.to_s.downcase)
        raise ValidationError, "cannot invite yourself"
      end

      token = SecureRandom.urlsafe_base64(48)
      token_digest = Digest::SHA256.hexdigest(token)
      expires_at = ENV.fetch("TENANT_INVITATION_TTL_HOURS", "168").to_i.hours.from_now

      invitation = ActiveRecord::Base.transaction do
        created = TenantInvitation.create!(
          tenant_id: Current.tenant_id,
          invited_by_user_id: Current.user.id,
          email: email,
          role: role,
          token_digest: token_digest,
          expires_at: expires_at
        )

        payload = IdentityDeliveryCipher.encrypt(
          "email" => email,
          "purpose" => "tenant_invitation",
          "token" => token,
          "tenant_id" => Current.tenant_id,
          "role" => role,
          "expires_at" => expires_at.iso8601
        )

        connection = ActiveRecord::Base.connection
        connection.exec_query(
          "SELECT crystell.enqueue_tenant_invitation_delivery($1::text, $2::text) AS outbox_id",
          "EnqueueTenantInvitationDelivery",
          [
            string_attribute("destination_fingerprint", DeliveryFingerprint.call(email)),
            string_attribute("encrypted_payload", payload)
          ]
        )

        SecurityAudit.record!(
          "tenant.invitation_created",
          metadata: { invitation_id: created.id, role: role }
        )

        created
      end

      Result.new(
        id: invitation.id,
        email: invitation.email,
        role: invitation.role,
        expires_at: invitation.expires_at,
        token: token
      )
    rescue ActiveRecord::RecordNotUnique
      raise ConflictError, "an active invitation already exists"
    end

    def self.validate!(email:, role:)
      raise ValidationError, "invalid email" unless email.match?(URI::MailTo::EMAIL_REGEXP)
      raise ValidationError, "invalid invitation role" unless ALLOWED_ROLES.include?(role)
    end
    private_class_method :validate!

    def self.string_attribute(name, value)
      ActiveRecord::Relation::QueryAttribute.new(name, value, ActiveRecord::Type::String.new)
    end
    private_class_method :string_attribute
  end
end
