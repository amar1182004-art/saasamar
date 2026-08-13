class AddTenantScopedInventoryRowLock < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.lock_inventory_level(
        p_store_id uuid,
        p_inventory_location_id uuid,
        p_product_variant_id uuid
      )
      RETURNS TABLE(
        on_hand bigint,
        reserved bigint,
        available bigint
      )
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public, crystell, pg_temp
      AS $$
      DECLARE
        v_tenant_id uuid;
      BEGIN
        v_tenant_id := crystell.current_tenant_id();
        IF v_tenant_id IS NULL THEN
          RAISE EXCEPTION 'inventory_lock_missing_tenant';
        END IF;

        RETURN QUERY
        SELECT
          level.on_hand,
          level.reserved,
          level.on_hand - level.reserved
        FROM inventory_levels AS level
        WHERE level.tenant_id = v_tenant_id
          AND level.store_id = p_store_id
          AND level.inventory_location_id = p_inventory_location_id
          AND level.product_variant_id = p_product_variant_id
        FOR UPDATE;
      END
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.lock_inventory_level(uuid, uuid, uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.lock_inventory_level(uuid, uuid, uuid) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.lock_inventory_level(uuid, uuid, uuid)"
  end
end
