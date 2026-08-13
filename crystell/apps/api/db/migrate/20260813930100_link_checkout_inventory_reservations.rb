class LinkCheckoutInventoryReservations < ActiveRecord::Migration[8.0]
  def up
    add_index :checkout_line_items,
              [:id, :tenant_id, :store_id, :product_variant_id],
              unique: true,
              name: "idx_checkout_lines_inventory_scope"
    add_index :inventory_reservations,
              [:id, :tenant_id, :store_id, :product_variant_id, :inventory_location_id],
              unique: true,
              name: "idx_inventory_reservations_checkout_scope"

    create_table :checkout_inventory_reservations, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :checkout_session_id, null: false
      t.uuid :checkout_line_item_id, null: false
      t.uuid :product_variant_id, null: false
      t.uuid :inventory_location_id, null: false
      t.uuid :inventory_reservation_id, null: false
      t.bigint :quantity, null: false
      t.timestamps
    end

    add_foreign_key :checkout_inventory_reservations, :tenants
    add_index :checkout_inventory_reservations,
              [:tenant_id, :store_id, :checkout_session_id, :checkout_line_item_id],
              name: "idx_checkout_inventory_line"
    add_index :checkout_inventory_reservations,
              [:tenant_id, :store_id, :checkout_line_item_id, :inventory_location_id],
              unique: true,
              name: "idx_checkout_inventory_location_unique"
    add_index :checkout_inventory_reservations,
              [:tenant_id, :store_id, :inventory_reservation_id],
              unique: true,
              name: "idx_checkout_inventory_reservation_unique"
    add_index :checkout_inventory_reservations,
              [:id, :tenant_id, :store_id],
              unique: true,
              name: "idx_checkout_inventory_id_scope"
    add_check_constraint :checkout_inventory_reservations,
                         "quantity > 0",
                         name: "checkout_inventory_quantity_check"

    execute <<~SQL
      ALTER TABLE checkout_inventory_reservations
      ADD CONSTRAINT checkout_inventory_session_scope_fk
      FOREIGN KEY (checkout_session_id, tenant_id, store_id)
      REFERENCES checkout_sessions(id, tenant_id, store_id)
    SQL
    execute <<~SQL
      ALTER TABLE checkout_inventory_reservations
      ADD CONSTRAINT checkout_inventory_line_variant_scope_fk
      FOREIGN KEY (checkout_line_item_id, tenant_id, store_id, product_variant_id)
      REFERENCES checkout_line_items(id, tenant_id, store_id, product_variant_id)
    SQL
    execute <<~SQL
      ALTER TABLE checkout_inventory_reservations
      ADD CONSTRAINT checkout_inventory_reservation_scope_fk
      FOREIGN KEY (inventory_reservation_id, tenant_id, store_id, product_variant_id, inventory_location_id)
      REFERENCES inventory_reservations(id, tenant_id, store_id, product_variant_id, inventory_location_id)
    SQL
    execute <<~SQL
      ALTER TABLE checkout_inventory_reservations
      ADD CONSTRAINT checkout_inventory_location_scope_fk
      FOREIGN KEY (inventory_location_id, tenant_id, store_id)
      REFERENCES inventory_locations(id, tenant_id, store_id)
    SQL

    execute "GRANT SELECT, INSERT ON checkout_inventory_reservations TO crystell_runtime"
    execute "ALTER TABLE checkout_inventory_reservations ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE checkout_inventory_reservations FORCE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY tenant_runtime_isolation ON checkout_inventory_reservations
      FOR ALL
      TO crystell_runtime
      USING (tenant_id = crystell.current_tenant_id())
      WITH CHECK (tenant_id = crystell.current_tenant_id())
    SQL
    execute <<~SQL
      DO $$
      BEGIN
        EXECUTE format(
          'CREATE POLICY migration_admin_access ON checkout_inventory_reservations FOR ALL TO %I USING (true) WITH CHECK (true)',
          current_user
        );
      END
      $$
    SQL
  end

  def down
    execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON checkout_inventory_reservations"
    execute "DROP POLICY IF EXISTS migration_admin_access ON checkout_inventory_reservations"
    drop_table :checkout_inventory_reservations
    remove_index :inventory_reservations, name: "idx_inventory_reservations_checkout_scope"
    remove_index :checkout_line_items, name: "idx_checkout_lines_inventory_scope"
  end
end
