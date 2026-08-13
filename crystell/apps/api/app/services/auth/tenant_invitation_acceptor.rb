require "digest"

module Auth
  class TenantInvitationAcceptor
    class InvalidInvitationError < StandardError; end

    Result = Data.define(:tenant_id)

    def self.call(user:, token:)
      digest = token_digest(token)
      raise InvalidInvitationError, "invalid invitation" unless digest

      tenant_id = IdentityScope.with(user.id) do
        row = ActiveRecord::Base.connection.exec_query(
          "SELECT crystell.accept_tenant_invitation($1::text) AS tenant_id",
          "AcceptTenantInvitation",
          [string_attribute("token_digest", digest)]
        ).first

        accepted_tenant_id = row&.fetch("tenant_id", nil)
        raise InvalidInvitationError, "invalid invitation" if accepted_tenant_id.blank?

        SecurityAudit.record!(
          "tenant.invitation_accepted",
          metadata: { tenant_id: accepted_tenant_id }
        )

        accepted_tenant_id
      end

      Result.new(tenant_id: tenant_id)
    end

    def self.token_digest(token)
      value = token.to_s
      return if value.blank? || value.bytesize > 512

      Digest::SHA256.hexdigest(value)
    end
    private_class_method :token_digest

    def self.string_attribute(name, value)
      ActiveRecord::Relation::QueryAttribute.new(name, value, ActiveRecord::Type::String.new)
    end
    private_class_method :string_attribute
  end
end
