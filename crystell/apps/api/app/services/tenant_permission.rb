class TenantPermission
  class ForbiddenError < StandardError; end

  PERMISSIONS = {
    "owner" => %w[
      tenant.manage
      ownership.transfer
      members.read
      members.invite
      members.manage
      stores.read
      stores.manage
      security.read
      dashboard.read
      billing.read
      billing.manage
      catalog.read
      catalog.manage
      inventory.read
      inventory.manage
      orders.read
      orders.manage
      payments.read
      payments.manage
      shipping.read
      shipping.manage
      support.read
      support.create
      support.manage
      notifications.read
      notifications.manage
    ],
    "admin" => %w[
      members.read
      members.invite
      stores.read
      stores.manage
      security.read
      dashboard.read
      billing.read
      catalog.read
      catalog.manage
      inventory.read
      inventory.manage
      orders.read
      orders.manage
      payments.read
      payments.manage
      shipping.read
      shipping.manage
      support.read
      support.create
      support.manage
      notifications.read
      notifications.manage
    ],
    "member" => %w[
      stores.read
      dashboard.read
      catalog.read
      inventory.read
      orders.read
      payments.read
      shipping.read
      support.read
      support.create
      notifications.read
    ]
  }.freeze

  def self.allowed?(membership, permission)
    return false unless membership&.status == "active"

    PERMISSIONS.fetch(membership.role, []).include?(permission.to_s)
  end

  def self.require!(membership, permission)
    return true if allowed?(membership, permission)

    raise ForbiddenError, "permission denied"
  end
end
