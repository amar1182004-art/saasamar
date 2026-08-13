class CreatePaymentFoundation < ActiveRecord::Migration[8.0]
  TENANT_TABLES = %w[
    payment_provider_accounts
    payment_intents
    payment_transactions
    payment_webhook_events
  ].freeze

  def up
    create_provider_accounts
    create_payment_intents
    create_payment_transactions
    create_webhook_events
    add_scope_foreign_keys
    configure_webhook_resolution
    configure_transaction_immutability
    configure_runtime_access
    configure_rls
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.resolve_payment_webhook_endpoint(uuid)"
    execute "DROP FUNCTION IF EXISTS crystell.prevent_payment_transaction_mutation()"

    TENANT_TABLES.each do |table|
      execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON #{table}"
      execute "DROP POLICY IF EXISTS migration_admin_access ON #{table}"
    end

    drop_table :payment_webhook_events
    drop_table :payment_transactions
    drop_table :payment_intents
    drop_table :payment_provider_accounts
  end

  private

  def create_provider_accounts
    create_table :payment_provider_accounts, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.string :provider_key, null: false
      t.string :mode, null: false, default: "test"
      t.string :status, null: false, default: "active"
      t.string :display_name
      t.text :credentials_ciphertext, null: false
      t.text :webhook_secret_ciphertext, null: false
      t.uuid :webhook_endpoint_id, null: false, default: -> { "gen_random_uuid()" }
      t.jsonb :public_config, null: false, default: {}
      t.datetime :last_verified_at
      t.timestamps
    end

    add_foreign_key :payment_provider_accounts, :tenants
    add_index :payment_provider_accounts,
              [:tenant_id, :store_id, :provider_key, :mode],
              unique: true,
              name: "idx_payment_accounts_provider_unique"
    add_index :payment_provider_accounts, :webhook_endpoint_id, unique: true
    add_index :payment_provider_accounts,
              [:id, :tenant_id, :store_id],
              unique: true,
              name: "idx_payment_accounts_id_tenant_store"
    add_check_constraint :payment_provider_accounts,
                         "provider_key ~ '^[a-z0-9][a-z0-9_.-]{1,63}$'",
                         name: "payment_accounts_provider_key_check"
    add_check_constraint :payment_provider_accounts,
                         "mode IN ('test', 'live')",
                         name: "payment_accounts_mode_check"
    add_check_constraint :payment_provider_accounts,
                         "status IN ('active', 'disabled')",
                         name: "payment_accounts_status_check"
  end

  def create_payment_intents
    create_table :payment_intents, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :order_id, null: false
      t.uuid :checkout_session_id, null: false
      t.uuid :payment_provider_account_id, null: false
      t.string :status, null: false, default: "created"
      t.string :currency, null: false
      t.bigint :amount_cents, null: false
      t.string :idempotency_key, null: false
      t.string :provider_intent_id
      t.string :provider_status
      t.text :checkout_url
      t.string :last_error_code
      t.text :last_error_message
      t.datetime :dispatched_at
      t.datetime :authorized_at
      t.datetime :paid_at
      t.datetime :failed_at
      t.integer :lock_version, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :payment_intents, :tenants
    add_index :payment_intents,
              [:tenant_id, :store_id, :idempotency_key],
              unique: true,
              name: "idx_payment_intents_idempotency"
    add_index :payment_intents,
              [:tenant_id, :store_id, :order_id],
              name: "idx_payment_intents_order"
    add_index :payment_intents,
              [:id, :tenant_id, :store_id],
              unique: true,
              name: "idx_payment_intents_id_tenant_store"
    add_index :payment_intents,
              [:payment_provider_account_id, :provider_intent_id],
              unique: true,
              where: "provider_intent_id IS NOT NULL",
              name: "idx_payment_intents_provider_reference"
    add_check_constraint :payment_intents,
                         "status IN ('created', 'pending', 'requires_action', 'authorized', 'paid', 'failed', 'cancelled')",
                         name: "payment_intents_status_check"
    add_check_constraint :payment_intents,
                         "currency = upper(currency) AND char_length(currency) = 3",
                         name: "payment_intents_currency_check"
    add_check_constraint :payment_intents,
                         "amount_cents >= 0",
                         name: "payment_intents_amount_check"
  end

  def create_payment_transactions
    create_table :payment_transactions, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :payment_intent_id, null: false
      t.string :kind, null: false
      t.string :status, null: false
      t.string :currency, null: false
      t.bigint :amount_cents, null: false
      t.string :idempotency_key, null: false
      t.string :provider_transaction_id
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :payment_transactions, :tenants
    add_index :payment_transactions,
              [:tenant_id, :store_id, :idempotency_key],
              unique: true,
              name: "idx_payment_transactions_idempotency"
    add_index :payment_transactions,
              [:tenant_id, :store_id, :payment_intent_id, :occurred_at],
              name: "idx_payment_transactions_intent"
    add_index :payment_transactions,
              [:id, :tenant_id, :store_id],
              unique: true,
              name: "idx_payment_transactions_id_tenant_store"
    add_check_constraint :payment_transactions,
                         "kind IN ('authorization', 'capture', 'refund', 'void', 'failure')",
                         name: "payment_transactions_kind_check"
    add_check_constraint :payment_transactions,
                         "status IN ('pending', 'succeeded', 'failed')",
                         name: "payment_transactions_status_check"
    add_check_constraint :payment_transactions,
                         "currency = upper(currency) AND char_length(currency) = 3",
                         name: "payment_transactions_currency_check"
    add_check_constraint :payment_transactions,
                         "amount_cents >= 0",
                         name: "payment_transactions_amount_check"
  end

  def create_webhook_events
    create_table :payment_webhook_events, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :payment_provider_account_id, null: false
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

    add_foreign_key :payment_webhook_events, :tenants
    add_index :payment_webhook_events,
              [:payment_provider_account_id, :provider_event_id],
              unique: true,
              name: "idx_payment_webhooks_provider_event"
    add_index :payment_webhook_events,
              [:tenant_id, :store_id, :status, :received_at],
              name: "idx_payment_webhooks_processing"
    add_index :payment_webhook_events,
              [:id, :tenant_id, :store_id],
              unique: true,
              name: "idx_payment_webhooks_id_tenant_store"
    add_check_constraint :payment_webhook_events,
                         "status IN ('received', 'processed', 'ignored', 'failed')",
                         name: "payment_webhooks_status_check"
  end

  def add_scope_foreign_keys
    execute "ALTER TABLE payment_provider_accounts ADD CONSTRAINT payment_accounts_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE payment_intents ADD CONSTRAINT payment_intents_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE payment_intents ADD CONSTRAINT payment_intents_order_scope_fk FOREIGN KEY (order_id, tenant_id, store_id) REFERENCES orders(id, tenant_id, store_id)"
    execute "ALTER TABLE payment_intents ADD CONSTRAINT payment_intents_checkout_scope_fk FOREIGN KEY (checkout_session_id, tenant_id, store_id) REFERENCES checkout_sessions(id, tenant_id, store_id)"
    execute "ALTER TABLE payment_intents ADD CONSTRAINT payment_intents_account_scope_fk FOREIGN KEY (payment_provider_account_id, tenant_id, store_id) REFERENCES payment_provider_accounts(id, tenant_id, store_id)"
    execute "ALTER TABLE payment_transactions ADD CONSTRAINT payment_transactions_intent_scope_fk FOREIGN KEY (payment_intent_id, tenant_id, store_id) REFERENCES payment_intents(id, tenant_id, store_id)"
    execute "ALTER TABLE payment_webhook_events ADD CONSTRAINT payment_webhooks_account_scope_fk FOREIGN KEY (payment_provider_account_id, tenant_id, store_id) REFERENCES payment_provider_accounts(id, tenant_id, store_id)"
  end

  def configure_webhook_resolution
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.resolve_payment_webhook_endpoint(p_endpoint_id uuid)
      RETURNS TABLE(
        tenant_id uuid,
        store_id uuid,
        payment_provider_account_id uuid,
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
        FROM payment_provider_accounts account
        WHERE account.webhook_endpoint_id = p_endpoint_id
        LIMIT 1
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.resolve_payment_webhook_endpoint(uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.resolve_payment_webhook_endpoint(uuid) TO crystell_runtime"
  end

  def configure_transaction_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_payment_transaction_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.is_runtime_role() THEN
          RAISE EXCEPTION 'payment_transactions_are_append_only';
        END IF;
        RETURN OLD;
      END
      $$
    SQL

    execute <<~SQL
      CREATE TRIGGER payment_transactions_append_only
      BEFORE UPDATE OR DELETE ON payment_transactions
      FOR EACH ROW EXECUTE FUNCTION crystell.prevent_payment_transaction_mutation()
    SQL
  end

  def configure_runtime_access
    execute "GRANT SELECT, INSERT, UPDATE ON payment_provider_accounts TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON payment_intents TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON payment_transactions TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON payment_webhook_events TO crystell_runtime"
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
