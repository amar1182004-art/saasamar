module Inventory
  class Adjuster
    class MissingTenantContextError < StandardError; end
    class InvalidAdjustmentError < StandardError; end
    class InsufficientStockError < StandardError; end
    class IdempotencyConflictError < StandardError; end

    Result = Data.define(:recorded, :ledger_entry_id, :on_hand, :reserved, :available)

    def self.call(store_id:, inventory_location_id:, product_variant_id:, delta_on_hand:, reason:, idempotency_key:, metadata: {})
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      TenantPermission.require!(Current.membership, "inventory.manage")

      delta = Integer(delta_on_hand)
      raise InvalidAdjustmentError, "delta_on_hand must not be zero" if delta.zero?
      raise InvalidAdjustmentError, "idempotency key is required" if idempotency_key.blank?
      raise InvalidAdjustmentError, "reason is required" if reason.blank?

      ledger = LedgerWriter.call(
        store_id: store_id,
        inventory_location_id: inventory_location_id,
        product_variant_id: product_variant_id,
        delta_on_hand: delta,
        delta_reserved: 0,
        reason: reason,
        idempotency_key: idempotency_key,
        metadata: metadata
      )

      Result.new(
        recorded: ledger.recorded,
        ledger_entry_id: ledger.ledger_entry_id,
        on_hand: ledger.on_hand,
        reserved: ledger.reserved,
        available: ledger.available
      )
    rescue ArgumentError, TypeError, LedgerWriter::InvalidChangeError => error
      raise InvalidAdjustmentError, error.message
    rescue LedgerWriter::InsufficientStockError => error
      raise InsufficientStockError, error.message
    rescue LedgerWriter::IdempotencyConflictError => error
      raise IdempotencyConflictError, error.message
    rescue LedgerWriter::MissingTenantContextError => error
      raise MissingTenantContextError, error.message
    end
  end
end
