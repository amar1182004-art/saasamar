module ControlPlane
  class Permission
    class ForbiddenError < StandardError; end

    ROLE_PERMISSIONS = {
      "viewer" => %w[
        platform.read
        tenant.read
        audit.read
        content.read
        feature_flags.read
      ],
      "operator" => %w[
        platform.read
        tenant.read
        tenant.support
        orders.read
        billing.read
        audit.read
        content.read
        feature_flags.read
      ],
      "admin" => %w[
        platform.read
        platform.manage
        tenant.read
        tenant.support
        tenant.manage
        orders.read
        orders.manage
        billing.read
        billing.manage
        audit.read
        security.read
        content.read
        content.manage
        feature_flags.read
        feature_flags.manage
      ],
      "owner" => ["*"]
    }.freeze

    def self.allowed?(user, permission)
      return false unless user&.status == "active"

      permissions = ROLE_PERMISSIONS.fetch(user.role, [])
      permissions.include?("*") || permissions.include?(permission.to_s)
    end

    def self.require!(user, permission)
      return true if allowed?(user, permission)

      raise ForbiddenError, "control plane permission is required: #{permission}"
    end
  end
end
