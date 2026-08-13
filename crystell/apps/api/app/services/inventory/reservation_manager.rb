module Inventory
  class ReservationManager
    class MissingTenantContextError < StandardError; end
    class InvalidReservationError < StandardError; end
    class InsufficientStockError < StandardError; end
    class InvalidTransitionError < StandardError; end
    class IdempotencyConflictError < StandardError; end

    Result = Data.define(:recorded, :reservation_id, :status, :on_hand, :reserved, :available)

    def self.reserve(store_id:, inventory_location_id:, product_variant_id:, quantity:, idempotency_key:, expires_at: nil, reference_type: nil, reference_id: nil, metadata: {})
      require_context_and_permission!

      requested_quantity = Integer(quantity)
      raise InvalidReservationError, "quantity must be positive" unless requested_quantity.positive?
      raise InvalidReservationError, "idempotency key is required" if idempotency_key.blank?

      result = nil

      ApplicationRecord.transaction(requires_new: true) do
        existing = InventoryReservation.find_by(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
        if existing
          verify_same_reservation!(existing, store_id, inventory_location_id, product_variant_id, requested_quantity)
          result = build_existing_result(existing)
          next
        end

        store = Store.find(store_id)
        location = InventoryLocation.find_by!(id: inventory_location_id, store_id: store.id, status: "active")
        variant = ProductVariant.find_by!(id: product_variant_id, store_id: store.id, status: "active")

        reservation = InventoryReservation.create!(
          tenant_id: Current.tenant_id,
          store_id: store.id,
          inventory_location_id: location.id,
          product_variant_id: variant.id,
          quantity: requested_quantity,
          status: "active",
          reference_type: reference_type,
          reference_id: reference_id,
          idempotency_key: idempotency_key,
          expires_at: expires_at,
          metadata: metadata
        )

        ledger = LedgerWriter.call(
          store_id: store.id,
          inventory_location_id: location.id,
          product_variant_id: variant.id,
          delta_on_hand: 0,
          delta_reserved: requested_quantity,
          reason: "reservation.created",
          idempotency_key: "reservation:#{reservation.id}:created",
          reference_type: "InventoryReservation",
          reference_id: reservation.id,
          metadata: {}
        )

        result = build_ledger_result(true, reservation, ledger)
      end

      result
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/inventory_reservations.*idempotency|idx_inventory_reservations_idempotency/i)

      existing = InventoryReservation.find_by!(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
      verify_same_reservation!(existing, store_id, inventory_location_id, product_variant_id, requested_quantity)
      build_existing_result(existing)
    rescue LedgerWriter::InsufficientStockError => error
      raise InsufficientStockError, error.message
    rescue LedgerWriter::IdempotencyConflictError => error
      raise IdempotencyConflictError, error.message
    end

    def self.release(reservation_id:)
      transition(reservation_id: reservation_id, target_status: "released")
    end

    def self.expire(reservation_id:)
      transition(reservation_id: reservation_id, target_status: "expired")
    end

    def self.consume(reservation_id:)
      require_context_and_permission!

      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        reservation = InventoryReservation.lock.find(reservation_id)

        if reservation.status == "consumed"
          result = build_existing_result(reservation)
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

        reservation.update!(status: "consumed", consumed_at: Time.current)
        result = build_ledger_result(true, reservation, ledger)
      end
      result
    rescue LedgerWriter::InsufficientStockError => error
      raise InsufficientStockError, error.message
    rescue LedgerWriter::IdempotencyConflictError, LedgerWriter::InconsistentStateError => error
      raise InvalidTransitionError, error.message
    end

    def self.transition(reservation_id:, target_status:)
      require_context_and_permission!

      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        reservation = InventoryReservation.lock.find(reservation_id)

        if reservation.status == target_status
          result = build_existing_result(reservation)
          next
        end
        raise InvalidTransitionError, "only active reservations can be #{target_status}" unless reservation.status == "active"

        ledger = LedgerWriter.call(
          store_id: reservation.store_id,
          inventory_location_id: reservation.inventory_location_id,
          product_variant_id: reservation.product_variant_id,
          delta_on_hand: 0,
          delta_reserved: -reservation.quantity,
          reason: "reservation.#{target_status}",
          idempotency_key: "reservation:#{reservation.id}:#{target_status}",
          reference_type: "InventoryReservation",
          reference_id: reservation.id,
          metadata: {}
        )

        attributes = { status: target_status }
        attributes[:released_at] = Time.current if target_status == "released"
        reservation.update!(attributes)

        result = build_ledger_result(true, reservation, ledger)
      end
      result
    rescue LedgerWriter::InsufficientStockError, LedgerWriter::IdempotencyConflictError, LedgerWriter::InconsistentStateError => error
      raise InvalidTransitionError, error.message
    end
    private_class_method :transition

    def self.require_context_and_permission!
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      TenantPermission.require!(Current.membership, "inventory.manage")
    end
    private_class_method :require_context_and_permission!

    def self.verify_same_reservation!(reservation, store_id, location_id, variant_id, quantity)
      same_request = reservation.store_id.to_s == store_id.to_s &&
        reservation.inventory_location_id.to_s == location_id.to_s &&
        reservation.product_variant_id.to_s == variant_id.to_s &&
        reservation.quantity == quantity
      return if same_request

      raise IdempotencyConflictError, "idempotency key was already used for a different reservation"
    end
    private_class_method :verify_same_reservation!

    def self.build_existing_result(reservation)
      level = InventoryLevel.find_by!(
        tenant_id: Current.tenant_id,
        store_id: reservation.store_id,
        inventory_location_id: reservation.inventory_location_id,
        product_variant_id: reservation.product_variant_id
      )

      Result.new(
        recorded: false,
        reservation_id: reservation.id,
        status: reservation.status,
        on_hand: level.on_hand,
        reserved: level.reserved,
        available: level.available
      )
    end
    private_class_method :build_existing_result

    def self.build_ledger_result(recorded, reservation, ledger)
      Result.new(
        recorded: recorded,
        reservation_id: reservation.id,
        status: reservation.status,
        on_hand: ledger.on_hand,
        reserved: ledger.reserved,
        available: ledger.available
      )
    end
    private_class_method :build_ledger_result
  end
end
