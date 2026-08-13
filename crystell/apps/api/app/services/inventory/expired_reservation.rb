module Inventory
  class ExpiredReservation
    class MissingTenantContextError < StandardError; end

    Result = Data.define(:expired, :reservation_id, :status, :on_hand, :reserved, :available)

    def self.call(reservation_id:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        reservation = InventoryReservation.lock.find(reservation_id)

        unless reservation.status == "active" && reservation.expires_at.present? && reservation.expires_at <= now
          level = InventoryLevel.find_by!(
            tenant_id: Current.tenant_id,
            store_id: reservation.store_id,
            inventory_location_id: reservation.inventory_location_id,
            product_variant_id: reservation.product_variant_id
          )
          result = Result.new(
            expired: false,
            reservation_id: reservation.id,
            status: reservation.status,
            on_hand: level.on_hand,
            reserved: level.reserved,
            available: level.available
          )
          next
        end

        ledger = LedgerWriter.call(
          store_id: reservation.store_id,
          inventory_location_id: reservation.inventory_location_id,
          product_variant_id: reservation.product_variant_id,
          delta_on_hand: 0,
          delta_reserved: -reservation.quantity,
          reason: "reservation.expired",
          idempotency_key: "reservation:#{reservation.id}:expired",
          reference_type: "InventoryReservation",
          reference_id: reservation.id,
          metadata: {}
        )

        reservation.update!(status: "expired")

        result = Result.new(
          expired: true,
          reservation_id: reservation.id,
          status: reservation.status,
          on_hand: ledger.on_hand,
          reserved: ledger.reserved,
          available: ledger.available
        )
      end

      result
    end
  end
end
