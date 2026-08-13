class CreateShippingFoundation < ActiveRecord::Migration[8.0]
  TENANT_TABLES = %w[shipping_provider_accounts shipping_rate_quotes shipments shipment_events].freeze

  def up
    create_provider_accounts
    create_rate_quotes
    create_shipments
    create_shipment_events
    add_scope_foreign_keys
    configure_event_immutability
    configure_runtime_access
    configure_rls
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.prevent_shipment_event_mutation()"
    TENANT_TABLES.each do |table|
      execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON #{table}"
      execute "DROP POLICY IF EXISTS migration_admin_access ON #{table}"
    end
    drop_table :shipment_events
    drop_table :shipments
    drop_table :shipping_rate_quotes
    drop_table :shipping_provider_accounts
  end

  private

  def create_provider_accounts
    create_table :shipping_provider_accounts, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.string :provider_key, null: false
      t.string :mode, null: false, default: "test"
      t.string :status, null: false, default: "active"
      t.string :display_name
      t.text :credentials_ciphertext, null: false
      t.jsonb :public_config, null: false, default: {}
      t.datetime :last_verified_at
      t.timestamps
    end
    add_foreign_key :shipping_provider_accounts, :tenants
    add_index :shipping_provider_accounts, [:tenant_id, :store_id, :provider_key, :mode], unique: true, name: "idx_shipping_accounts_provider_unique"
    add_index :shipping_provider_accounts, [:id, :tenant_id, :store_id], unique: true, name: "idx_shipping_accounts_id_tenant_store"
    add_check_constraint :shipping_provider_accounts, "provider_key ~ '^[a-z0-9][a-z0-9_.-]{1,63}$'", name: "shipping_accounts_provider_key_check"
    add_check_constraint :shipping_provider_accounts, "mode IN ('test', 'live')", name: "shipping_accounts_mode_check"
    add_check_constraint :shipping_provider_accounts, "status IN ('active', 'disabled')", name: "shipping_accounts_status_check"
  end

  def create_rate_quotes
    create_table :shipping_rate_quotes, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :checkout_session_id, null: false
      t.uuid :shipping_provider_account_id, null: false
      t.string :provider_quote_id
      t.string :service_code, null: false
      t.string :service_name, null: false
      t.string :currency, null: false
      t.bigint :amount_cents, null: false
      t.datetime :expires_at, null: false
      t.string :request_digest, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :shipping_rate_quotes, :tenants
    add_index :shipping_rate_quotes, [:tenant_id, :store_id, :checkout_session_id, :request_digest, :service_code], unique: true, name: "idx_shipping_quotes_request_service"
    add_index :shipping_rate_quotes, [:id, :tenant_id, :store_id], unique: true, name: "idx_shipping_quotes_id_tenant_store"
    add_check_constraint :shipping_rate_quotes, "currency = upper(currency) AND char_length(currency) = 3", name: "shipping_quotes_currency_check"
    add_check_constraint :shipping_rate_quotes, "amount_cents >= 0", name: "shipping_quotes_amount_check"
  end

  def create_shipments
    create_table :shipments, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :order_id, null: false
      t.uuid :shipping_provider_account_id, null: false
      t.string :status, null: false, default: "pending"
      t.string :service_code, null: false
      t.string :currency, null: false
      t.bigint :shipping_cost_cents, null: false, default: 0
      t.string :idempotency_key, null: false
      t.string :provider_shipment_id
      t.string :tracking_number
      t.text :tracking_url
      t.text :label_url
      t.jsonb :destination_snapshot, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :submitted_at
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.datetime :cancelled_at
      t.timestamps
    end
    add_foreign_key :shipments, :tenants
    add_index :shipments, [:tenant_id, :store_id, :idempotency_key], unique: true, name: "idx_shipments_idempotency"
    add_index :shipments, [:shipping_provider_account_id, :provider_shipment_id], unique: true, where: "provider_shipment_id IS NOT NULL", name: "idx_shipments_provider_reference"
    add_index :shipments, [:id, :tenant_id, :store_id], unique: true, name: "idx_shipments_id_tenant_store"
    add_check_constraint :shipments, "status IN ('pending', 'submitted', 'label_ready', 'in_transit', 'delivered', 'failed', 'cancelled')", name: "shipments_status_check"
    add_check_constraint :shipments, "currency = upper(currency) AND char_length(currency) = 3", name: "shipments_currency_check"
    add_check_constraint :shipments, "shipping_cost_cents >= 0", name: "shipments_cost_check"
  end

  def create_shipment_events
    create_table :shipment_events, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :shipment_id, null: false
      t.string :event_type, null: false
      t.string :provider_event_id
      t.string :status
      t.string :location
      t.text :message
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :shipment_events, :tenants
    add_index :shipment_events, [:tenant_id, :store_id, :shipment_id, :occurred_at], name: "idx_shipment_events_timeline"
    add_index :shipment_events, [:shipment_id, :provider_event_id], unique: true, where: "provider_event_id IS NOT NULL", name: "idx_shipment_events_provider_event"
  end

  def add_scope_foreign_keys
    execute "ALTER TABLE shipping_provider_accounts ADD CONSTRAINT shipping_accounts_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE shipping_rate_quotes ADD CONSTRAINT shipping_quotes_checkout_scope_fk FOREIGN KEY (checkout_session_id, tenant_id, store_id) REFERENCES checkout_sessions(id, tenant_id, store_id)"
    execute "ALTER TABLE shipping_rate_quotes ADD CONSTRAINT shipping_quotes_account_scope_fk FOREIGN KEY (shipping_provider_account_id, tenant_id, store_id) REFERENCES shipping_provider_accounts(id, tenant_id, store_id)"
    execute "ALTER TABLE shipments ADD CONSTRAINT shipments_order_scope_fk FOREIGN KEY (order_id, tenant_id, store_id) REFERENCES orders(id, tenant_id, store_id)"
    execute "ALTER TABLE shipments ADD CONSTRAINT shipments_account_scope_fk FOREIGN KEY (shipping_provider_account_id, tenant_id, store_id) REFERENCES shipping_provider_accounts(id, tenant_id, store_id)"
    execute "ALTER TABLE shipment_events ADD CONSTRAINT shipment_events_shipment_scope_fk FOREIGN KEY (shipment_id, tenant_id, store_id) REFERENCES shipments(id, tenant_id, store_id)"
  end

  def configure_event_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_shipment_event_mutation()
      RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF crystell.is_runtime_role() THEN
          RAISE EXCEPTION 'shipment_events_are_append_only';
        END IF;
        RETURN OLD;
      END
      $$
    SQL
    execute "CREATE TRIGGER shipment_events_append_only BEFORE UPDATE OR DELETE ON shipment_events FOR EACH ROW EXECUTE FUNCTION crystell.prevent_shipment_event_mutation()"
  end

  def configure_runtime_access
    execute "GRANT SELECT, INSERT, UPDATE ON shipping_provider_accounts TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON shipping_rate_quotes TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON shipments TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON shipment_events TO crystell_runtime"
  end

  def configure_rls
    TENANT_TABLES.each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
      execute "CREATE POLICY tenant_runtime_isolation ON #{table} FOR ALL TO crystell_runtime USING (tenant_id = crystell.current_tenant_id()) WITH CHECK (tenant_id = crystell.current_tenant_id())"
      execute <<~SQL
        DO $$
        BEGIN
          EXECUTE format('CREATE POLICY migration_admin_access ON #{table} FOR ALL TO %I USING (true) WITH CHECK (true)', current_user);
        END
        $$
      SQL
    end
  end
end
