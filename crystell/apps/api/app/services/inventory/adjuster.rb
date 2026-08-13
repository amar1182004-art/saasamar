module Inventory
  class Adjuster
    class MissingTenantContextError < StandardError; end
    class InvalidAdjustmentError < StandardError; end
    class InsufficientStockError < StandardError; end

    Result = Data.define(:recorded, :ledger_entry_id, :on_hand, :reserved, :available)

    def self.call(store_id:, inventory_location_id:, product_variant_id:, delta_on_hand:, reason:, idempotency_key:, metadata: {})
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      TenantPermission.require!(Current.membership, "inventory.manage")

      delta = Integer(delta_on_hand)
      raise InvalidAdjustmentError, "delta_on_hand must not be zero" if delta.zero?
      raise InvalidAdjustmentError, "idempotency key is required" if idempotency_key.blank?
      raise InvalidAdjustmentError, "reason is required" if reason.blank?

      result = nil

      ApplicationRecord.transaction(requires_new: true) do
        existing = InventoryLedgerEntry.find_by(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
        if existing
          level = InventoryLevel.find_by!(
            tenant_id: Current.tenant_id,
            store_id: existing.store_id,
            inventory_location_id: existing.inventory_location_id,
            product_variant_id: existing.product_variant_id
          )
          result = build_result(false, existing, level)
          next
        end

        store = Store.find(store_id)
        location = InventoryLocation.find_by!(id: inventory_location_id, store_id: store.id)
        variant = ProductVariant.find_by!(id: product_variant_id, store_id: store.id)

        level = InventoryLevel.create_or_find_by!(
          tenant_id: Current.tenant_id,
          store_id: store.id,
          inventory_location_id: location.id,
          product_variant_id: variant.id
        )
        level.lock!

        new_on_hand = level.on_hand + delta
        raise InsufficientStockError, "adjustment would make on-hand stock negative" if new_on_hand.negative?
        raise InsufficientStockError, "adjustment would reduce on-hand stock below reserved stock" if new_on_hand < level.reserved

        level.update!(on_hand: new_on_hand)

        entry = InventoryLedgerEntry.create!(
          tenant_id: Current.tenant_id,
          store_id: store.id,
          inventory_location_id: location.id,
          product_variant_id: variant.id,
          delta_on_hand: delta,
          delta_reserved: 0,
          reason: reason,
          actor_user_id: Current.user&.id,
          idempotency_key: idempotency_key,
          metadata: metadata
        )

        result = build_result(true, entry, level)
      end

      result
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/inventory_ledger.*idempotency|idx_inventory_ledger_idempotency/i)

      existing = InventoryLedgerEntry.find_by!(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
      level = InventoryLevel.find_by!(
        tenant_id: Current.tenant_id,
        store_id: existing.store_id,
        inventory_location_id: existing.inventory_location_id,
        product_variant_id: existing.product_variant_id
      )
      build_result(false, existing, level)
    end

    def self.build_result(recorded, entry, level)
      Result.new(
        recorded: recorded,
        ledger_entry_id: entry.id,
        on_hand: level.on_hand,
        reserved: level.reserved,
        available: level.available
      )
    end
    private_class_method :build_result
  end
end
