class CreateCatalogAndInventoryFoundation < ActiveRecord::Migration[8.0]
  TENANT_TABLES = %w[
    products
    product_variants
    categories
    product_category_assignments
    inventory_locations
    inventory_levels
    inventory_ledger_entries
    inventory_reservations
  ].freeze

  def up
    add_index :stores, [:id, :tenant_id], unique: true, name: "idx_stores_id_tenant" unless index_exists?(:stores, [:id, :tenant_id], name: "idx_stores_id_tenant")

    create_table :products, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.string :title, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.text :description
      t.string :vendor
      t.string :product_type
      t.string :seo_title
      t.text :seo_description
      t.datetime :published_at
      t.integer :lock_version, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :products, :tenants
    add_index :products, [:tenant_id, :store_id, :status], name: "idx_products_tenant_store_status"
    add_index :products, [:id, :tenant_id, :store_id], unique: true, name: "idx_products_id_tenant_store"
    add_check_constraint :products, "status IN ('draft', 'active', 'archived')", name: "products_status_check"
    execute "CREATE UNIQUE INDEX idx_products_store_slug_ci ON products (tenant_id, store_id, lower(slug))"

    create_table :product_variants, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :product_id, null: false
      t.string :title, null: false
      t.string :sku
      t.string :barcode
      t.string :currency, null: false
      t.bigint :price_cents, null: false, default: 0
      t.bigint :compare_at_price_cents
      t.bigint :cost_cents
      t.integer :position, null: false, default: 0
      t.boolean :taxable, null: false, default: true
      t.boolean :track_inventory, null: false, default: true
      t.bigint :weight_grams
      t.string :status, null: false, default: "active"
      t.jsonb :option_values, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :product_variants, :tenants
    add_index :product_variants, [:tenant_id, :store_id, :product_id, :position], name: "idx_variants_product_position"
    add_index :product_variants, [:id, :tenant_id, :store_id], unique: true, name: "idx_variants_id_tenant_store"
    add_check_constraint :product_variants, "status IN ('active', 'archived')", name: "product_variants_status_check"
    add_check_constraint :product_variants, "currency = upper(currency) AND char_length(currency) = 3", name: "product_variants_currency_check"
    add_check_constraint :product_variants, "price_cents >= 0", name: "product_variants_price_check"
    add_check_constraint :product_variants, "compare_at_price_cents IS NULL OR compare_at_price_cents >= price_cents", name: "product_variants_compare_price_check"
    add_check_constraint :product_variants, "cost_cents IS NULL OR cost_cents >= 0", name: "product_variants_cost_check"
    add_check_constraint :product_variants, "weight_grams IS NULL OR weight_grams >= 0", name: "product_variants_weight_check"
    execute "CREATE UNIQUE INDEX idx_variants_store_sku_ci ON product_variants (tenant_id, store_id, lower(sku)) WHERE sku IS NOT NULL AND btrim(sku) <> ''"
    execute "CREATE UNIQUE INDEX idx_variants_store_barcode_ci ON product_variants (tenant_id, store_id, lower(barcode)) WHERE barcode IS NOT NULL AND btrim(barcode) <> ''"

    create_table :categories, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :parent_id
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :status, null: false, default: "active"
      t.integer :position, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :categories, :tenants
    add_index :categories, [:tenant_id, :store_id, :parent_id, :position], name: "idx_categories_tree_position"
    add_index :categories, [:id, :tenant_id, :store_id], unique: true, name: "idx_categories_id_tenant_store"
    add_check_constraint :categories, "status IN ('active', 'archived')", name: "categories_status_check"
    execute "CREATE UNIQUE INDEX idx_categories_store_slug_ci ON categories (tenant_id, store_id, lower(slug))"

    create_table :product_category_assignments, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :product_id, null: false
      t.uuid :category_id, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :product_category_assignments, :tenants
    add_index :product_category_assignments, [:tenant_id, :store_id, :product_id, :category_id], unique: true, name: "idx_product_category_unique"
    add_index :product_category_assignments, [:tenant_id, :store_id, :category_id, :position], name: "idx_product_category_position"

    create_table :inventory_locations, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.string :name, null: false
      t.string :code, null: false
      t.string :status, null: false, default: "active"
      t.integer :priority, null: false, default: 0
      t.jsonb :address, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :inventory_locations, :tenants
    add_index :inventory_locations, [:tenant_id, :store_id, :status, :priority], name: "idx_inventory_locations_status_priority"
    add_index :inventory_locations, [:id, :tenant_id, :store_id], unique: true, name: "idx_inventory_locations_id_tenant_store"
    add_check_constraint :inventory_locations, "status IN ('active', 'inactive')", name: "inventory_locations_status_check"
    execute "CREATE UNIQUE INDEX idx_inventory_locations_store_code_ci ON inventory_locations (tenant_id, store_id, lower(code))"

    create_table :inventory_levels, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :inventory_location_id, null: false
      t.uuid :product_variant_id, null: false
      t.bigint :on_hand, null: false, default: 0
      t.bigint :reserved, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :inventory_levels, :tenants
    add_index :inventory_levels, [:tenant_id, :store_id, :inventory_location_id, :product_variant_id], unique: true, name: "idx_inventory_levels_location_variant"
    add_check_constraint :inventory_levels, "on_hand >= 0", name: "inventory_levels_on_hand_check"
    add_check_constraint :inventory_levels, "reserved >= 0", name: "inventory_levels_reserved_check"
    add_check_constraint :inventory_levels, "reserved <= on_hand", name: "inventory_levels_reserved_capacity_check"

    create_table :inventory_ledger_entries, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :inventory_location_id, null: false
      t.uuid :product_variant_id, null: false
      t.bigint :delta_on_hand, null: false, default: 0
      t.bigint :delta_reserved, null: false, default: 0
      t.string :reason, null: false
      t.string :reference_type
      t.uuid :reference_id
      t.uuid :actor_user_id
      t.string :idempotency_key, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end
    add_foreign_key :inventory_ledger_entries, :tenants
    add_foreign_key :inventory_ledger_entries, :users, column: :actor_user_id
    add_index :inventory_ledger_entries, [:tenant_id, :idempotency_key], unique: true, name: "idx_inventory_ledger_idempotency"
    add_index :inventory_ledger_entries, [:tenant_id, :store_id, :product_variant_id, :occurred_at], name: "idx_inventory_ledger_variant_time"
    add_check_constraint :inventory_ledger_entries, "delta_on_hand <> 0 OR delta_reserved <> 0", name: "inventory_ledger_nonzero_delta_check"

    create_table :inventory_reservations, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :inventory_location_id, null: false
      t.uuid :product_variant_id, null: false
      t.bigint :quantity, null: false
      t.string :status, null: false, default: "active"
      t.string :reference_type
      t.uuid :reference_id
      t.string :idempotency_key, null: false
      t.datetime :expires_at
      t.datetime :released_at
      t.datetime :consumed_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :inventory_reservations, :tenants
    add_index :inventory_reservations, [:tenant_id, :idempotency_key], unique: true, name: "idx_inventory_reservations_idempotency"
    add_index :inventory_reservations, [:tenant_id, :store_id, :product_variant_id, :status, :expires_at], name: "idx_inventory_reservations_variant_status"
    add_check_constraint :inventory_reservations, "quantity > 0", name: "inventory_reservations_quantity_check"
    add_check_constraint :inventory_reservations, "status IN ('active', 'released', 'consumed', 'expired')", name: "inventory_reservations_status_check"

    add_composite_foreign_keys
    configure_runtime_access
    configure_rls
    configure_ledger_immutability
  end

  def down
    execute "DROP TRIGGER IF EXISTS inventory_ledger_entries_append_only ON inventory_ledger_entries"
    execute "DROP FUNCTION IF EXISTS crystell.prevent_inventory_ledger_mutation()"

    TENANT_TABLES.each do |table|
      execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON #{table}"
      execute "DROP POLICY IF EXISTS migration_admin_access ON #{table}"
    end

    drop_table :inventory_reservations
    drop_table :inventory_ledger_entries
    drop_table :inventory_levels
    drop_table :inventory_locations
    drop_table :product_category_assignments
    drop_table :categories
    drop_table :product_variants
    drop_table :products

    remove_index :stores, name: "idx_stores_id_tenant" if index_exists?(:stores, name: "idx_stores_id_tenant")
  end

  private

  def add_composite_foreign_keys
    execute "ALTER TABLE products ADD CONSTRAINT products_store_tenant_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE product_variants ADD CONSTRAINT variants_product_scope_fk FOREIGN KEY (product_id, tenant_id, store_id) REFERENCES products(id, tenant_id, store_id)"
    execute "ALTER TABLE categories ADD CONSTRAINT categories_store_tenant_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE categories ADD CONSTRAINT categories_parent_scope_fk FOREIGN KEY (parent_id, tenant_id, store_id) REFERENCES categories(id, tenant_id, store_id) DEFERRABLE INITIALLY DEFERRED"
    execute "ALTER TABLE product_category_assignments ADD CONSTRAINT product_category_product_scope_fk FOREIGN KEY (product_id, tenant_id, store_id) REFERENCES products(id, tenant_id, store_id)"
    execute "ALTER TABLE product_category_assignments ADD CONSTRAINT product_category_category_scope_fk FOREIGN KEY (category_id, tenant_id, store_id) REFERENCES categories(id, tenant_id, store_id)"
    execute "ALTER TABLE inventory_locations ADD CONSTRAINT inventory_locations_store_tenant_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE inventory_levels ADD CONSTRAINT inventory_levels_location_scope_fk FOREIGN KEY (inventory_location_id, tenant_id, store_id) REFERENCES inventory_locations(id, tenant_id, store_id)"
    execute "ALTER TABLE inventory_levels ADD CONSTRAINT inventory_levels_variant_scope_fk FOREIGN KEY (product_variant_id, tenant_id, store_id) REFERENCES product_variants(id, tenant_id, store_id)"
    execute "ALTER TABLE inventory_ledger_entries ADD CONSTRAINT inventory_ledger_location_scope_fk FOREIGN KEY (inventory_location_id, tenant_id, store_id) REFERENCES inventory_locations(id, tenant_id, store_id)"
    execute "ALTER TABLE inventory_ledger_entries ADD CONSTRAINT inventory_ledger_variant_scope_fk FOREIGN KEY (product_variant_id, tenant_id, store_id) REFERENCES product_variants(id, tenant_id, store_id)"
    execute "ALTER TABLE inventory_reservations ADD CONSTRAINT inventory_reservations_location_scope_fk FOREIGN KEY (inventory_location_id, tenant_id, store_id) REFERENCES inventory_locations(id, tenant_id, store_id)"
    execute "ALTER TABLE inventory_reservations ADD CONSTRAINT inventory_reservations_variant_scope_fk FOREIGN KEY (product_variant_id, tenant_id, store_id) REFERENCES product_variants(id, tenant_id, store_id)"
  end

  def configure_runtime_access
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON products, product_variants, categories, product_category_assignments, inventory_locations, inventory_levels, inventory_reservations TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON inventory_ledger_entries TO crystell_runtime"
  end

  def configure_rls
    TENANT_TABLES.each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
      execute <<~SQL
        CREATE POLICY tenant_runtime_isolation ON #{table}
        FOR ALL
        TO crystell_runtime
        USING (tenant_id = crystell.current_tenant_id())
        WITH CHECK (tenant_id = crystell.current_tenant_id())
      SQL
      execute <<~SQL
        DO $$
        BEGIN
          EXECUTE format(
            'CREATE POLICY migration_admin_access ON #{table} FOR ALL TO %I USING (true) WITH CHECK (true)',
            current_user
          );
        END
        $$
      SQL
    end
  end

  def configure_ledger_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_inventory_ledger_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_runtime() THEN
          RAISE EXCEPTION 'inventory_ledger_entries are append-only for runtime roles';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL

    execute <<~SQL
      CREATE TRIGGER inventory_ledger_entries_append_only
      BEFORE UPDATE OR DELETE ON inventory_ledger_entries
      FOR EACH ROW EXECUTE FUNCTION crystell.prevent_inventory_ledger_mutation()
    SQL
  end
end
