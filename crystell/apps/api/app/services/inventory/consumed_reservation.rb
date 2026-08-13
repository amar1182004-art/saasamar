module Inventory
  class ConsumedReservation
    class MissingTenantContextError < StandardError; end
    class InvalidTransitionError < StandardError; end

    Result = Data.define(:consumed, :reservation_id, :status, :on_hand, :reserved, :available)

    def self.call(reservation_id:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        reservation = InventoryReservation.lock.find(reservation_id)

        if reservation.status == "consumed"
          level = InventoryLevel.find_by!(
            tenant_id: Current.tenant_id,
            store_id: reservation.store_id,
            inventory_location_id: reservation.inventory_location_id,
            product_variant_id: reservation.product_variant_id
          )
          result = Result.new(
            consumed: false,
            reservation_id: reservation.id,
            status: reservation.status,
            on_hand: level.on_hand,
            reserved: level.reserved,
            available: level.available
          )
          next
        end

        raise InvalidTransitionError, "only active reservations can be consumed" unless reservation.status == "active"

        ledger = LedgerWriter.call(
          store_id: reservation.store_id,
          inventory_location_id: reservation.inventory_location_id,
          product_variant_id: reservation.product_variant_id,
          delta_on_hand: -reservation.quantity,
          delta_reserved: -reservation.quantity,
          reason: "reservation.consumed",
          idempotency_key: "reservation:#{reservation.id}:consumed",
          reference_type: "InventoryReservation",
          reference_id: reservation.id,
          metadata: {}
        )

        reservation.update!(status: "consumed", consumed_at: now)
        result = Result.new(
          consumed: true,
          reservation_id: reservation.id,
          status: reservation.status,
          on_hand: ledger.on_hand,
          reserved: ledger.reserved,
          available: ledger.available
        )
      end

      result
    rescue LedgerWriter::InsufficientStockError, LedgerWriter::IdempotencyConflictError, LedgerWriter::InconsistentStateError => error
      raise InvalidTransitionError, error.message
    end
  end
end
