class MakeInventoryLedgerAuthoritative < ActiveRecord::Migration[8.0]
  def up
    execute "REVOKE INSERT, UPDATE, DELETE ON inventory_levels FROM crystell_runtime"
    execute "REVOKE INSERT ON inventory_ledger_entries FROM crystell_runtime"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.apply_inventory_change(
        p_store_id uuid,
        p_inventory_location_id uuid,
        p_product_variant_id uuid,
        p_delta_on_hand bigint,
        p_delta_reserved bigint,
        p_reason text,
        p_idempotency_key text,
        p_reference_type text,
        p_reference_id uuid,
        p_metadata jsonb
      )
      RETURNS TABLE(
        recorded boolean,
        ledger_entry_id uuid,
        on_hand bigint,
        reserved bigint,
        available bigint
      )
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_tenant_id uuid;
        v_actor_user_id uuid;
        v_existing public.inventory_ledger_entries%ROWTYPE;
        v_level public.inventory_levels%ROWTYPE;
        v_new_on_hand bigint;
        v_new_reserved bigint;
        v_ledger_entry_id uuid;
        v_metadata jsonb := COALESCE(p_metadata, '{}'::jsonb);
      BEGIN
        v_tenant_id := crystell.current_tenant_id();
        IF v_tenant_id IS NULL THEN
          RAISE EXCEPTION 'inventory_change_missing_tenant';
        END IF;

        IF COALESCE(p_delta_on_hand, 0) = 0 AND COALESCE(p_delta_reserved, 0) = 0 THEN
          RAISE EXCEPTION 'inventory_change_invalid';
        END IF;
        IF p_reason IS NULL OR btrim(p_reason) = '' OR p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
          RAISE EXCEPTION 'inventory_change_invalid';
        END IF;

        BEGIN
          v_actor_user_id := NULLIF(current_setting('app.current_user_id', true), '')::uuid;
        EXCEPTION WHEN invalid_text_representation THEN
          v_actor_user_id := NULL;
        END;

        PERFORM pg_advisory_xact_lock(
          hashtextextended(v_tenant_id::text || ':' || p_idempotency_key, 0)
        );

        PERFORM 1
        FROM public.stores
        WHERE id = p_store_id AND tenant_id = v_tenant_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'inventory_change_scope_invalid';
        END IF;

        PERFORM 1
        FROM public.inventory_locations
        WHERE id = p_inventory_location_id
          AND tenant_id = v_tenant_id
          AND store_id = p_store_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'inventory_change_scope_invalid';
        END IF;

        PERFORM 1
        FROM public.product_variants
        WHERE id = p_product_variant_id
          AND tenant_id = v_tenant_id
          AND store_id = p_store_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'inventory_change_scope_invalid';
        END IF;

        SELECT *
        INTO v_existing
        FROM public.inventory_ledger_entries
        WHERE tenant_id = v_tenant_id
          AND idempotency_key = p_idempotency_key;

        IF FOUND THEN
          IF v_existing.store_id IS DISTINCT FROM p_store_id
            OR v_existing.inventory_location_id IS DISTINCT FROM p_inventory_location_id
            OR v_existing.product_variant_id IS DISTINCT FROM p_product_variant_id
            OR v_existing.delta_on_hand IS DISTINCT FROM p_delta_on_hand
            OR v_existing.delta_reserved IS DISTINCT FROM p_delta_reserved
            OR v_existing.reason IS DISTINCT FROM p_reason
            OR v_existing.reference_type IS DISTINCT FROM p_reference_type
            OR v_existing.reference_id IS DISTINCT FROM p_reference_id
            OR v_existing.metadata IS DISTINCT FROM v_metadata THEN
            RAISE EXCEPTION 'inventory_change_idempotency_conflict';
          END IF;

          SELECT *
          INTO v_level
          FROM public.inventory_levels
          WHERE tenant_id = v_tenant_id
            AND store_id = p_store_id
            AND inventory_location_id = p_inventory_location_id
            AND product_variant_id = p_product_variant_id;

          IF NOT FOUND THEN
            RAISE EXCEPTION 'inventory_change_state_inconsistent';
          END IF;

          RETURN QUERY SELECT false, v_existing.id, v_level.on_hand, v_level.reserved, v_level.on_hand - v_level.reserved;
          RETURN;
        END IF;

        INSERT INTO public.inventory_levels (
          id, tenant_id, store_id, inventory_location_id, product_variant_id,
          on_hand, reserved, lock_version, created_at, updated_at
        ) VALUES (
          gen_random_uuid(), v_tenant_id, p_store_id, p_inventory_location_id, p_product_variant_id,
          0, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
        ON CONFLICT (tenant_id, store_id, inventory_location_id, product_variant_id) DO NOTHING;

        SELECT *
        INTO v_level
        FROM public.inventory_levels
        WHERE tenant_id = v_tenant_id
          AND store_id = p_store_id
          AND inventory_location_id = p_inventory_location_id
          AND product_variant_id = p_product_variant_id
        FOR UPDATE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'inventory_change_state_inconsistent';
        END IF;

        v_new_on_hand := v_level.on_hand + p_delta_on_hand;
        v_new_reserved := v_level.reserved + p_delta_reserved;

        IF v_new_on_hand < 0 OR v_new_reserved < 0 OR v_new_reserved > v_new_on_hand THEN
          RAISE EXCEPTION 'inventory_change_insufficient_stock';
        END IF;

        INSERT INTO public.inventory_ledger_entries (
          id, tenant_id, store_id, inventory_location_id, product_variant_id,
          delta_on_hand, delta_reserved, reason, reference_type, reference_id,
          actor_user_id, idempotency_key, metadata, occurred_at, created_at, updated_at
        ) VALUES (
          gen_random_uuid(), v_tenant_id, p_store_id, p_inventory_location_id, p_product_variant_id,
          p_delta_on_hand, p_delta_reserved, p_reason, p_reference_type, p_reference_id,
          v_actor_user_id, p_idempotency_key, v_metadata, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
        RETURNING id INTO v_ledger_entry_id;

        UPDATE public.inventory_levels
        SET on_hand = v_new_on_hand,
            reserved = v_new_reserved,
            lock_version = lock_version + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_level.id;

        RETURN QUERY SELECT true, v_ledger_entry_id, v_new_on_hand, v_new_reserved, v_new_on_hand - v_new_reserved;
      END;
      $$
    SQL

    execute <<~SQL
      REVOKE ALL ON FUNCTION crystell.apply_inventory_change(
        uuid, uuid, uuid, bigint, bigint, text, text, text, uuid, jsonb
      ) FROM PUBLIC
    SQL
    execute <<~SQL
      GRANT EXECUTE ON FUNCTION crystell.apply_inventory_change(
        uuid, uuid, uuid, bigint, bigint, text, text, text, uuid, jsonb
      ) TO crystell_runtime
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS crystell.apply_inventory_change(
        uuid, uuid, uuid, bigint, bigint, text, text, text, uuid, jsonb
      )
    SQL
    execute "GRANT INSERT, UPDATE, DELETE ON inventory_levels TO crystell_runtime"
    execute "GRANT INSERT ON inventory_ledger_entries TO crystell_runtime"
  end
end
