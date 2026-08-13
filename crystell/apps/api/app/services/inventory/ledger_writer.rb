module Inventory
  class LedgerWriter
    class MissingTenantContextError < StandardError; end
    class InvalidChangeError < StandardError; end
    class InsufficientStockError < StandardError; end
    class IdempotencyConflictError < StandardError; end
    class InconsistentStateError < StandardError; end

    Result = Data.define(:recorded, :ledger_entry_id, :on_hand, :reserved, :available)

    def self.call(
      store_id:,
      inventory_location_id:,
      product_variant_id:,
      delta_on_hand:,
      delta_reserved:,
      reason:,
      idempotency_key:,
      reference_type: nil,
      reference_id: nil,
      metadata: {}
    )
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      on_hand_delta = Integer(delta_on_hand)
      reserved_delta = Integer(delta_reserved)
      raise InvalidChangeError, "inventory change must have a non-zero delta" if on_hand_delta.zero? && reserved_delta.zero?
      raise InvalidChangeError, "reason is required" if reason.blank?
      raise InvalidChangeError, "idempotency key is required" if idempotency_key.blank?

      connection = ApplicationRecord.connection
      sql = <<~SQL
        SELECT *
        FROM crystell.apply_inventory_change(
          #{connection.quote(store_id)}::uuid,
          #{connection.quote(inventory_location_id)}::uuid,
          #{connection.quote(product_variant_id)}::uuid,
          #{connection.quote(on_hand_delta)}::bigint,
          #{connection.quote(reserved_delta)}::bigint,
          #{connection.quote(reason.to_s)}::text,
          #{connection.quote(idempotency_key.to_s)}::text,
          #{connection.quote(reference_type)}::text,
          #{connection.quote(reference_id)}::uuid,
          #{connection.quote(metadata.to_json)}::jsonb
        )
      SQL
      row = connection.select_one(sql)

      Result.new(
        recorded: ActiveModel::Type::Boolean.new.cast(row.fetch("recorded")),
        ledger_entry_id: row.fetch("ledger_entry_id"),
        on_hand: Integer(row.fetch("on_hand")),
        reserved: Integer(row.fetch("reserved")),
        available: Integer(row.fetch("available"))
      )
    rescue ArgumentError, TypeError
      raise InvalidChangeError, "inventory deltas must be integers"
    rescue ActiveRecord::StatementInvalid => error
      translate_database_error!(error)
    end

    def self.translate_database_error!(error)
      message = error.message

      raise InsufficientStockError, "inventory change exceeds available stock" if message.include?("inventory_change_insufficient_stock")
      raise IdempotencyConflictError, "idempotency key was already used for a different inventory change" if message.include?("inventory_change_idempotency_conflict")
      raise ActiveRecord::RecordNotFound, "inventory scope not found" if message.include?("inventory_change_scope_invalid")
      raise InconsistentStateError, "inventory state is inconsistent" if message.include?("inventory_change_state_inconsistent")
      raise MissingTenantContextError, "tenant context is required" if message.include?("inventory_change_missing_tenant")
      raise InvalidChangeError, "invalid inventory change" if message.include?("inventory_change_invalid")

      raise error
    end
    private_class_method :translate_database_error!
  end
end
