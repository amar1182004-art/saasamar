class CreateCheckoutAndOrdersFoundation < ActiveRecord::Migration[8.0]
  TENANT_TABLES = %w[
    carts
    cart_items
    checkout_sessions
    checkout_line_items
    store_order_sequences
    orders
    order_items
  ].freeze

  def up
    create_carts
    create_checkout
    create_orders
    add_scope_foreign_keys
    configure_order_numbering
    configure_runtime_access
    configure_rls
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.next_store_order_number(uuid)"
    TENANT_TABLES.each do |table|
      execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON #{table}"
      execute "DROP POLICY IF EXISTS migration_admin_access ON #{table}"
    end

    drop_table :order_items
    drop_table :orders
    drop_table :store_order_sequences
    drop_table :checkout_line_items
    drop_table :checkout_sessions
    drop_table :cart_items
    drop_table :carts
  end

  private

  def create_carts
    create_table :carts, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.string :access_token_digest, null: false
      t.string :status, null: false, default: "active"
      t.string :currency
      t.datetime :expires_at, null: false
      t.integer :lock_version, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :carts, :tenants
    add_index :carts, [:tenant_id, :store_id, :access_token_digest], unique: true, name: "idx_carts_store_token_digest"
    add_index :carts, [:id, :tenant_id, :store_id], unique: true, name: "idx_carts_id_tenant_store"
    add_index :carts, [:tenant_id, :store_id, :status, :expires_at], name: "idx_carts_status_expiry"
    add_check_constraint :carts, "status IN ('active', 'checking_out', 'converted', 'abandoned', 'expired')", name: "carts_status_check"
    add_check_constraint :carts, "currency IS NULL OR (currency = upper(currency) AND char_length(currency) = 3)", name: "carts_currency_check"

    create_table :cart_items, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :cart_id, null: false
      t.uuid :product_variant_id, null: false
      t.bigint :quantity, null: false
      t.timestamps
    end
    add_foreign_key :cart_items, :tenants
    add_index :cart_items, [:tenant_id, :store_id, :cart_id, :product_variant_id], unique: true, name: "idx_cart_items_variant_unique"
    add_index :cart_items, [:id, :tenant_id, :store_id], unique: true, name: "idx_cart_items_id_tenant_store"
    add_check_constraint :cart_items, "quantity > 0", name: "cart_items_quantity_check"
  end

  def create_checkout
    create_table :checkout_sessions, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :cart_id, null: false
      t.string :status, null: false, default: "open"
      t.string :currency, null: false
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :shipping_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :customer_email
      t.jsonb :shipping_address, null: false, default: {}
      t.jsonb :billing_address, null: false, default: {}
      t.string :idempotency_key, null: false
      t.datetime :priced_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :completed_at
      t.integer :lock_version, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :checkout_sessions, :tenants
    add_index :checkout_sessions, [:tenant_id, :idempotency_key], unique: true, name: "idx_checkout_idempotency"
    add_index :checkout_sessions, [:tenant_id, :store_id, :cart_id], name: "idx_checkout_cart"
    add_index :checkout_sessions, [:id, :tenant_id, :store_id], unique: true, name: "idx_checkout_id_tenant_store"
    add_check_constraint :checkout_sessions, "status IN ('open', 'inventory_reserved', 'payment_pending', 'completed', 'expired', 'cancelled')", name: "checkout_status_check"
    add_check_constraint :checkout_sessions, "currency = upper(currency) AND char_length(currency) = 3", name: "checkout_currency_check"
    add_money_constraints(:checkout_sessions, "checkout")

    create_table :checkout_line_items, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :checkout_session_id, null: false
      t.uuid :product_id, null: false
      t.uuid :product_variant_id, null: false
      t.string :product_title, null: false
      t.string :variant_title, null: false
      t.string :sku
      t.string :currency, null: false
      t.bigint :unit_price_cents, null: false
      t.bigint :quantity, null: false
      t.bigint :line_subtotal_cents, null: false
      t.boolean :taxable, null: false, default: true
      t.jsonb :option_values, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :checkout_line_items, :tenants
    add_index :checkout_line_items, [:tenant_id, :store_id, :checkout_session_id, :product_variant_id], unique: true, name: "idx_checkout_lines_variant_unique"
    add_index :checkout_line_items, [:id, :tenant_id, :store_id], unique: true, name: "idx_checkout_lines_id_tenant_store"
    add_check_constraint :checkout_line_items, "quantity > 0", name: "checkout_lines_quantity_check"
    add_check_constraint :checkout_line_items, "unit_price_cents >= 0", name: "checkout_lines_unit_price_check"
    add_check_constraint :checkout_line_items, "line_subtotal_cents = unit_price_cents * quantity", name: "checkout_lines_subtotal_check"
    add_check_constraint :checkout_line_items, "currency = upper(currency) AND char_length(currency) = 3", name: "checkout_lines_currency_check"
  end

  def create_orders
    create_table :store_order_sequences, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.bigint :current_number, null: false, default: 1000
      t.timestamps
    end
    add_foreign_key :store_order_sequences, :tenants
    add_index :store_order_sequences, [:tenant_id, :store_id], unique: true, name: "idx_order_sequences_tenant_store"
    add_check_constraint :store_order_sequences, "current_number >= 1000", name: "order_sequences_number_check"

    create_table :orders, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :checkout_session_id, null: false
      t.bigint :order_number, null: false
      t.string :status, null: false, default: "pending"
      t.string :payment_status, null: false, default: "unpaid"
      t.string :fulfillment_status, null: false, default: "unfulfilled"
      t.string :currency, null: false
      t.bigint :subtotal_cents, null: false
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :shipping_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false
      t.string :customer_email
      t.jsonb :shipping_address, null: false, default: {}
      t.jsonb :billing_address, null: false, default: {}
      t.datetime :placed_at
      t.datetime :cancelled_at
      t.integer :lock_version, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :orders, :tenants
    add_index :orders, [:tenant_id, :store_id, :order_number], unique: true, name: "idx_orders_store_number"
    add_index :orders, [:tenant_id, :store_id, :checkout_session_id], unique: true, name: "idx_orders_checkout_unique"
    add_index :orders, [:id, :tenant_id, :store_id], unique: true, name: "idx_orders_id_tenant_store"
    add_index :orders, [:tenant_id, :store_id, :created_at], name: "idx_orders_store_created"
    add_check_constraint :orders, "order_number > 0", name: "orders_number_check"
    add_check_constraint :orders, "status IN ('pending', 'confirmed', 'cancelled', 'closed')", name: "orders_status_check"
    add_check_constraint :orders, "payment_status IN ('unpaid', 'pending', 'authorized', 'paid', 'partially_refunded', 'refunded', 'failed')", name: "orders_payment_status_check"
    add_check_constraint :orders, "fulfillment_status IN ('unfulfilled', 'partial', 'fulfilled', 'returned', 'cancelled')", name: "orders_fulfillment_status_check"
    add_check_constraint :orders, "currency = upper(currency) AND char_length(currency) = 3", name: "orders_currency_check"
    add_money_constraints(:orders, "orders")

    create_table :order_items, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :order_id, null: false
      t.uuid :product_id
      t.uuid :product_variant_id
      t.string :product_title, null: false
      t.string :variant_title, null: false
      t.string :sku
      t.string :currency, null: false
      t.bigint :unit_price_cents, null: false
      t.bigint :quantity, null: false
      t.bigint :line_subtotal_cents, null: false
      t.boolean :taxable, null: false, default: true
      t.jsonb :option_values, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :order_items, :tenants
    add_index :order_items, [:tenant_id, :store_id, :order_id], name: "idx_order_items_order"
    add_index :order_items, [:id, :tenant_id, :store_id], unique: true, name: "idx_order_items_id_tenant_store"
    add_check_constraint :order_items, "quantity > 0", name: "order_items_quantity_check"
    add_check_constraint :order_items, "unit_price_cents >= 0", name: "order_items_unit_price_check"
    add_check_constraint :order_items, "line_subtotal_cents = unit_price_cents * quantity", name: "order_items_subtotal_check"
    add_check_constraint :order_items, "currency = upper(currency) AND char_length(currency) = 3", name: "order_items_currency_check"
  end

  def add_money_constraints(table, prefix)
    add_check_constraint table, "subtotal_cents >= 0", name: "#{prefix}_subtotal_check"
    add_check_constraint table, "discount_cents >= 0 AND discount_cents <= subtotal_cents", name: "#{prefix}_discount_check"
    add_check_constraint table, "shipping_cents >= 0", name: "#{prefix}_shipping_check"
    add_check_constraint table, "tax_cents >= 0", name: "#{prefix}_tax_check"
    add_check_constraint table, "total_cents = subtotal_cents - discount_cents + shipping_cents + tax_cents", name: "#{prefix}_total_formula_check"
  end

  def add_scope_foreign_keys
    execute "ALTER TABLE carts ADD CONSTRAINT carts_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE cart_items ADD CONSTRAINT cart_items_cart_scope_fk FOREIGN KEY (cart_id, tenant_id, store_id) REFERENCES carts(id, tenant_id, store_id)"
    execute "ALTER TABLE cart_items ADD CONSTRAINT cart_items_variant_scope_fk FOREIGN KEY (product_variant_id, tenant_id, store_id) REFERENCES product_variants(id, tenant_id, store_id)"
    execute "ALTER TABLE checkout_sessions ADD CONSTRAINT checkout_cart_scope_fk FOREIGN KEY (cart_id, tenant_id, store_id) REFERENCES carts(id, tenant_id, store_id)"
    execute "ALTER TABLE checkout_line_items ADD CONSTRAINT checkout_lines_checkout_scope_fk FOREIGN KEY (checkout_session_id, tenant_id, store_id) REFERENCES checkout_sessions(id, tenant_id, store_id)"
    execute "ALTER TABLE checkout_line_items ADD CONSTRAINT checkout_lines_product_scope_fk FOREIGN KEY (product_id, tenant_id, store_id) REFERENCES products(id, tenant_id, store_id)"
    execute "ALTER TABLE checkout_line_items ADD CONSTRAINT checkout_lines_variant_scope_fk FOREIGN KEY (product_variant_id, tenant_id, store_id) REFERENCES product_variants(id, tenant_id, store_id)"
    execute "ALTER TABLE store_order_sequences ADD CONSTRAINT order_sequences_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE orders ADD CONSTRAINT orders_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE orders ADD CONSTRAINT orders_checkout_scope_fk FOREIGN KEY (checkout_session_id, tenant_id, store_id) REFERENCES checkout_sessions(id, tenant_id, store_id)"
    execute "ALTER TABLE order_items ADD CONSTRAINT order_items_order_scope_fk FOREIGN KEY (order_id, tenant_id, store_id) REFERENCES orders(id, tenant_id, store_id)"
  end

  def configure_order_numbering
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.next_store_order_number(p_store_id uuid)
      RETURNS bigint
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public, crystell, pg_temp
      AS $$
      DECLARE
        v_tenant_id uuid;
        v_number bigint;
      BEGIN
        v_tenant_id := crystell.current_tenant_id();
        IF v_tenant_id IS NULL THEN
          RAISE EXCEPTION 'order_number_missing_tenant';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM stores WHERE id = p_store_id AND tenant_id = v_tenant_id) THEN
          RAISE EXCEPTION 'order_number_store_scope_invalid';
        END IF;

        INSERT INTO store_order_sequences (id, tenant_id, store_id, current_number, created_at, updated_at)
        VALUES (gen_random_uuid(), v_tenant_id, p_store_id, 1001, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (tenant_id, store_id)
        DO UPDATE SET current_number = store_order_sequences.current_number + 1, updated_at = CURRENT_TIMESTAMP
        RETURNING current_number INTO v_number;

        RETURN v_number;
      END
      $$
    SQL
    execute "REVOKE ALL ON FUNCTION crystell.next_store_order_number(uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.next_store_order_number(uuid) TO crystell_runtime"
  end

  def configure_runtime_access
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON carts, cart_items TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON checkout_sessions TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON checkout_line_items TO crystell_runtime"
    execute "GRANT SELECT ON store_order_sequences TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON orders TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON order_items TO crystell_runtime"
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
end
