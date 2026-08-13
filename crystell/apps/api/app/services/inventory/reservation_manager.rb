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
          level = level_for(existing)
          result = build_result(false, existing, level)
          next
        end

        store = Store.find(store_id)
        location = InventoryLocation.find_by!(id: inventory_location_id, store_id: store.id, status: "active")
        variant = ProductVariant.find_by!(id: product_variant_id, store_id: store.id, status: "active")

        level = InventoryLevel.create_or_find_by!(
          tenant_id: Current.tenant_id,
          store_id: store.id,
          inventory_location_id: location.id,
          product_variant_id: variant.id
        )
        level.lock!

        raise InsufficientStockError, "not enough available inventory" if level.available < requested_quantity

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

        level.update!(reserved: level.reserved + requested_quantity)
        append_ledger!(
          level: level,
          delta_on_hand: 0,
          delta_reserved: requested_quantity,
          reason: "reservation.created",
          idempotency_key: "reservation:#{reservation.id}:created",
          reference_type: "InventoryReservation",
          reference_id: reservation.id
        )

        result = build_result(true, reservation, level)
      end

      result
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/inventory_reservations.*idempotency|idx_inventory_reservations_idempotency/i)

      existing = InventoryReservation.find_by!(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
      verify_same_reservation!(existing, store_id, inventory_location_id, product_variant_id, requested_quantity)
      build_result(false, existing, level_for(existing))
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
        level = level_for(reservation, lock: true)

        if reservation.status == "consumed"
          result = build_result(false, reservation, level)
          next
        end
        raise InvalidTransitionError, "only active reservations can be consumed" unless reservation.status == "active"

        new_on_hand = level.on_hand - reservation.quantity
        new_reserved = level.reserved - reservation.quantity
        raise InsufficientStockError, "reservation exceeds on-hand inventory" if new_on_hand.negative?
        raise InvalidTransitionError, "reservation accounting is inconsistent" if new_reserved.negative?

        level.update!(on_hand: new_on_hand, reserved: new_reserved)
        reservation.update!(status: "consumed", consumed_at: Time.current)
        append_ledger!(
          level: level,
          delta_on_hand: -reservation.quantity,
          delta_reserved: -reservation.quantity,
          reason: "reservation.consumed",
          idempotency_key: "reservation:#{reservation.id}:consumed",
          reference_type: "InventoryReservation",
          reference_id: reservation.id
        )

        result = build_result(true, reservation, level)
      end
      result
    end

    def self.transition(reservation_id:, target_status:)
      require_context_and_permission!

      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        reservation = InventoryReservation.lock.find(reservation_id)
        level = level_for(reservation, lock: true)

        if reservation.status == target_status
          result = build_result(false, reservation, level)
          next
        end
        raise InvalidTransitionError, "only active reservations can be #{target_status}" unless reservation.status == "active"

        new_reserved = level.reserved - reservation.quantity
        raise InvalidTransitionError, "reservation accounting is inconsistent" if new_reserved.negative?

        level.update!(reserved: new_reserved)
        timestamp = Time.current
        attributes = { status: target_status }
        attributes[:released_at] = timestamp if target_status == "released"
        reservation.update!(attributes)

        append_ledger!(
          level: level,
          delta_on_hand: 0,
          delta_reserved: -reservation.quantity,
          reason: "reservation.#{target_status}",
          idempotency_key: "reservation:#{reservation.id}:#{target_status}",
          reference_type: "InventoryReservation",
          reference_id: reservation.id
        )

        result = build_result(true, reservation, level)
      end
      result
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

    def self.level_for(reservation, lock: false)
      scope = InventoryLevel.where(
        tenant_id: Current.tenant_id,
        store_id: reservation.store_id,
        inventory_location_id: reservation.inventory_location_id,
        product_variant_id: reservation.product_variant_id
      )
      scope = scope.lock if lock
      scope.first!
    end
    private_class_method :level_for

    def self.append_ledger!(level:, delta_on_hand:, delta_reserved:, reason:, idempotency_key:, reference_type:, reference_id:)
      InventoryLedgerEntry.create!(
        tenant_id: Current.tenant_id,
        store_id: level.store_id,
        inventory_location_id: level.inventory_location_id,
        product_variant_id: level.product_variant_id,
        delta_on_hand: delta_on_hand,
        delta_reserved: delta_reserved,
        reason: reason,
        reference_type: reference_type,
        reference_id: reference_id,
        actor_user_id: Current.user&.id,
        idempotency_key: idempotency_key,
        metadata: {}
      )
    end
    private_class_method :append_ledger!

    def self.build_result(recorded, reservation, level)
      Result.new(
        recorded: recorded,
        reservation_id: reservation.id,
        status: reservation.status,
        on_hand: level.on_hand,
        reserved: level.reserved,
        available: level.available
      )
    end
    private_class_method :build_result
  end
end
