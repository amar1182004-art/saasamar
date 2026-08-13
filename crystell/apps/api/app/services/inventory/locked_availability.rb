module Inventory
  class LockedAvailability
    class MissingTenantContextError < StandardError; end

    Result = Data.define(:on_hand, :reserved, :available)

    def self.call(store_id:, inventory_location_id:, product_variant_id:)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      connection = ApplicationRecord.connection
      row = connection.select_one(<<~SQL)
        SELECT *
        FROM crystell.lock_inventory_level(
          #{connection.quote(store_id)}::uuid,
          #{connection.quote(inventory_location_id)}::uuid,
          #{connection.quote(product_variant_id)}::uuid
        )
      SQL
      return nil unless row

      Result.new(
        on_hand: Integer(row.fetch("on_hand")),
        reserved: Integer(row.fetch("reserved")),
        available: Integer(row.fetch("available"))
      )
    rescue ActiveRecord::StatementInvalid => error
      raise MissingTenantContextError, "tenant context is required" if error.message.include?("inventory_lock_missing_tenant")

      raise
    end
  end
end
