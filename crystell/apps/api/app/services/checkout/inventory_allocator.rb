require "securerandom"

module Checkout
  class InventoryAllocator
    class MissingTenantContextError < StandardError; end
    class InvalidCheckoutError < StandardError; end
    class InsufficientStockError < StandardError; end
    class InconsistentReservationError < StandardError; end

    Result = Data.define(:checkout_session_id, :status, :reservation_ids, :reserved_quantity)

    def self.call(checkout_session_id:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        checkout = CheckoutSession.lock.find(checkout_session_id)
        raise InvalidCheckoutError, "checkout has expired" if checkout.expires_at <= now

        if checkout.status == "inventory_reserved"
          result = build_existing_result(checkout)
          next
        end
        raise InvalidCheckoutError, "checkout must be open before inventory allocation" unless checkout.status == "open"

        lines = CheckoutLineItem.where(checkout_session_id: checkout.id)
                                .includes(:product_variant)
                                .order(:product_variant_id, :id)
                                .to_a
        raise InvalidCheckoutError, "checkout must contain at least one line" if lines.empty?

        location_ids = InventoryLocation.where(store_id: checkout.store_id, status: "active")
                                        .order(:priority, :id)
                                        .pluck(:id)

        lines.each do |line|
          variant = line.product_variant
          next unless variant.track_inventory

          remaining = line.quantity
          location_ids.each do |location_id|
            break if remaining.zero?

            level = InventoryLevel.lock.find_by(
              tenant_id: Current.tenant_id,
              store_id: checkout.store_id,
              inventory_location_id: location_id,
              product_variant_id: variant.id
            )
            next unless level

            available = level.available
            next unless available.positive?

            quantity = [remaining, available].min
            reservation = InventoryReservation.create!(
              tenant_id: Current.tenant_id,
              store_id: checkout.store_id,
              inventory_location_id: location_id,
              product_variant_id: variant.id,
              quantity: quantity,
              status: "active",
              reference_type: "CheckoutLineItem",
              reference_id: line.id,
              idempotency_key: "checkout:#{checkout.id}:line:#{line.id}:location:#{location_id}",
              expires_at: checkout.expires_at,
              metadata: { "checkout_session_id" => checkout.id }
            )

            Inventory::LedgerWriter.call(
              store_id: checkout.store_id,
              inventory_location_id: location_id,
              product_variant_id: variant.id,
              delta_on_hand: 0,
              delta_reserved: quantity,
              reason: "checkout.inventory_reserved",
              idempotency_key: "reservation:#{reservation.id}:created",
              reference_type: "InventoryReservation",
              reference_id: reservation.id,
              metadata: { "checkout_session_id" => checkout.id, "checkout_line_item_id" => line.id }
            )

            CheckoutInventoryReservation.create!(
              tenant_id: Current.tenant_id,
              store_id: checkout.store_id,
              checkout_session_id: checkout.id,
              checkout_line_item_id: line.id,
              product_variant_id: variant.id,
              inventory_location_id: location_id,
              inventory_reservation_id: reservation.id,
              quantity: quantity
            )

            remaining -= quantity
          end

          raise InsufficientStockError, "insufficient inventory for checkout line #{line.id}" if remaining.positive?
        end

        checkout.update!(status: "inventory_reserved")
        result = build_existing_result(checkout)
      end

      result
    rescue Inventory::LedgerWriter::InsufficientStockError => error
      raise InsufficientStockError, error.message
    end

    def self.build_existing_result(checkout)
      mappings = CheckoutInventoryReservation.where(checkout_session_id: checkout.id)
                                             .order(:checkout_line_item_id, :inventory_location_id)
                                             .to_a
      reservation_ids = mappings.map(&:inventory_reservation_id)
      if reservation_ids.any?
        active_count = InventoryReservation.active.where(id: reservation_ids).count
        raise InconsistentReservationError, "checkout inventory reservations are no longer active" unless active_count == reservation_ids.length
      end

      Result.new(
        checkout_session_id: checkout.id,
        status: checkout.status,
        reservation_ids: reservation_ids,
        reserved_quantity: mappings.sum(&:quantity)
      )
    end
    private_class_method :build_existing_result
  end
end
