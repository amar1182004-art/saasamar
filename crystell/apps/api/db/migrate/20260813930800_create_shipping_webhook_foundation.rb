class CreateShippingWebhookFoundation < ActiveRecord::Migration[8.0]
  def up
    add_column :shipping_provider_accounts, :webhook_secret_ciphertext, :text
    add_column :shipping_provider_accounts, :webhook_endpoint_id, :uuid, null: false, default: -> { "gen_random_uuid()" }
    add_index :shipping_provider_accounts, :webhook_endpoint_id, unique: true, name: "idx_shipping_accounts_webhook_endpoint"

    create_table :shipping_webhook_events, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :shipping_provider_account_id, null: false
      t.uuid :shipment_id
      t.string :provider_event_id, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "received"
      t.string :payload_digest, null: false
      t.string :signature_digest, null: false
      t.text :raw_body_ciphertext, null: false
      t.datetime :received_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :processed_at
      t.text :failure_reason
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :shipping_webhook_events, :tenants
    add_index :shipping_webhook_events,
              [:shipping_provider_account_id, :provider_event_id],
              unique: true,
              name: "idx_shipping_webhooks_provider_event"
    add_index :shipping_webhook_events,
              [:tenant_id, :store_id, :status, :received_at],
              name: "idx_shipping_webhooks_processing"
    add_index :shipping_webhook_events,
              [:id, :tenant_id, :store_id],
              unique: true,
              name: "idx_shipping_webhooks_id_tenant_store"

    add_check_constraint :shipping_webhook_events,
                         "status IN ('received', 'processed', 'ignored', 'failed')",
                         name: "shipping_webhooks_status_check"

    execute "ALTER TABLE shipping_webhook_events ADD CONSTRAINT shipping_webhooks_account_scope_fk FOREIGN KEY (shipping_provider_account_id, tenant_id, store_id) REFERENCES shipping_provider_accounts(id, tenant_id, store_id)"
    execute "ALTER TABLE shipping_webhook_events ADD CONSTRAINT shipping_webhooks_shipment_scope_fk FOREIGN KEY (shipment_id, tenant_id, store_id) REFERENCES shipments(id, tenant_id, store_id)"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.resolve_shipping_webhook_endpoint(p_endpoint_id uuid)
      RETURNS TABLE(
        tenant_id uuid,
        store_id uuid,
        shipping_provider_account_id uuid,
        provider_key text,
        account_status text
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = public, crystell, pg_temp
      AS $$
        SELECT account.tenant_id,
               account.store_id,
               account.id,
               account.provider_key,
               account.status
        FROM shipping_provider_accounts account
        WHERE account.webhook_endpoint_id = p_endpoint_id
        LIMIT 1
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.resolve_shipping_webhook_endpoint(uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.resolve_shipping_webhook_endpoint(uuid) TO crystell_runtime"

    execute "GRANT SELECT, INSERT, UPDATE ON shipping_webhook_events TO crystell_runtime"
    execute "ALTER TABLE shipping_webhook_events ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE shipping_webhook_events FORCE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY tenant_runtime_isolation ON shipping_webhook_events
      FOR ALL
      TO crystell_runtime
      USING (tenant_id = crystell.current_tenant_id())
      WITH CHECK (tenant_id = crystell.current_tenant_id())
    SQL
    execute <<~SQL
      DO $$
      BEGIN
        EXECUTE format(
          'CREATE POLICY migration_admin_access ON shipping_webhook_events FOR ALL TO %I USING (true) WITH CHECK (true)',
          current_user
        );
      END
      $$
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.resolve_shipping_webhook_endpoint(uuid)"
    execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON shipping_webhook_events"
    execute "DROP POLICY IF EXISTS migration_admin_access ON shipping_webhook_events"
    drop_table :shipping_webhook_events
    remove_index :shipping_provider_accounts, name: "idx_shipping_accounts_webhook_endpoint"
    remove_column :shipping_provider_accounts, :webhook_endpoint_id
    remove_column :shipping_provider_accounts, :webhook_secret_ciphertext
  end
end
