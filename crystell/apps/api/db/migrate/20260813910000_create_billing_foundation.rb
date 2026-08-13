class CreateBillingFoundation < ActiveRecord::Migration[8.0]
  TENANT_TABLES = %w[subscriptions invoices usage_events usage_totals billing_events].freeze

  def up
    create_table :billing_plans, id: :uuid do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.integer :position, null: false, default: 0
      t.integer :trial_days, null: false, default: 0
      t.boolean :public, null: false, default: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :billing_plans, :code, unique: true
    add_check_constraint :billing_plans, "status IN ('draft', 'active', 'archived')", name: "billing_plans_status_check"
    add_check_constraint :billing_plans, "trial_days >= 0", name: "billing_plans_trial_days_check"

    create_table :billing_prices, id: :uuid do |t|
      t.references :billing_plan, type: :uuid, null: false, foreign_key: true
      t.string :currency, null: false
      t.string :interval, null: false
      t.bigint :amount_cents, null: false
      t.string :status, null: false, default: "active"
      t.string :provider, null: true
      t.string :external_price_id, null: true
      t.timestamps
    end
    add_index :billing_prices, [:billing_plan_id, :currency, :interval], unique: true, name: "idx_billing_prices_plan_currency_interval"
    add_index :billing_prices, [:provider, :external_price_id], unique: true, where: "external_price_id IS NOT NULL", name: "idx_billing_prices_provider_external"
    add_check_constraint :billing_prices, "currency = upper(currency) AND char_length(currency) = 3", name: "billing_prices_currency_check"
    add_check_constraint :billing_prices, "interval IN ('monthly', 'annual')", name: "billing_prices_interval_check"
    add_check_constraint :billing_prices, "amount_cents >= 0", name: "billing_prices_amount_check"
    add_check_constraint :billing_prices, "status IN ('active', 'archived')", name: "billing_prices_status_check"

    create_table :billing_features, id: :uuid do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :value_type, null: false, default: "boolean"
      t.string :unit, null: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :billing_features, :key, unique: true
    add_check_constraint :billing_features, "value_type IN ('boolean', 'integer', 'decimal', 'string')", name: "billing_features_value_type_check"

    create_table :billing_entitlements, id: :uuid do |t|
      t.references :billing_plan, type: :uuid, null: false, foreign_key: true
      t.references :billing_feature, type: :uuid, null: false, foreign_key: true
      t.jsonb :value, null: false, default: {}
      t.timestamps
    end
    add_index :billing_entitlements, [:billing_plan_id, :billing_feature_id], unique: true, name: "idx_billing_entitlements_plan_feature"

    create_table :subscriptions, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.references :billing_plan, type: :uuid, null: false, foreign_key: true
      t.references :billing_price, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false, default: "trialing"
      t.string :currency, null: false
      t.string :interval, null: false
      t.bigint :amount_cents, null: false
      t.datetime :started_at, null: false
      t.datetime :trial_ends_at
      t.datetime :current_period_start, null: false
      t.datetime :current_period_end, null: false
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :canceled_at
      t.string :provider
      t.string :external_subscription_id
      t.integer :lock_version, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :subscriptions, :tenants
    add_index :subscriptions, [:tenant_id, :status]
    add_index :subscriptions, [:provider, :external_subscription_id], unique: true, where: "external_subscription_id IS NOT NULL", name: "idx_subscriptions_provider_external"
    add_check_constraint :subscriptions, "status IN ('trialing', 'active', 'past_due', 'paused', 'canceled', 'expired')", name: "subscriptions_status_check"
    add_check_constraint :subscriptions, "currency = upper(currency) AND char_length(currency) = 3", name: "subscriptions_currency_check"
    add_check_constraint :subscriptions, "interval IN ('monthly', 'annual')", name: "subscriptions_interval_check"
    add_check_constraint :subscriptions, "amount_cents >= 0", name: "subscriptions_amount_check"
    add_check_constraint :subscriptions, "current_period_end > current_period_start", name: "subscriptions_period_check"

    create_table :invoices, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.references :subscription, type: :uuid, null: true, foreign_key: true
      t.string :number, null: false
      t.string :status, null: false, default: "draft"
      t.string :currency, null: false
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :amount_paid_cents, null: false, default: 0
      t.datetime :issued_at
      t.datetime :due_at
      t.datetime :paid_at
      t.string :provider
      t.string :external_invoice_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :invoices, :tenants
    add_index :invoices, [:tenant_id, :number], unique: true
    add_index :invoices, [:tenant_id, :status]
    add_index :invoices, [:provider, :external_invoice_id], unique: true, where: "external_invoice_id IS NOT NULL", name: "idx_invoices_provider_external"
    add_check_constraint :invoices, "status IN ('draft', 'open', 'paid', 'void', 'uncollectible')", name: "invoices_status_check"
    add_check_constraint :invoices, "currency = upper(currency) AND char_length(currency) = 3", name: "invoices_currency_check"
    add_check_constraint :invoices, "subtotal_cents >= 0 AND discount_cents >= 0 AND tax_cents >= 0 AND total_cents >= 0 AND amount_paid_cents >= 0", name: "invoices_amounts_check"

    create_table :usage_events, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.references :billing_feature, type: :uuid, null: false, foreign_key: true
      t.string :idempotency_key, null: false
      t.decimal :quantity, precision: 20, scale: 6, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :usage_events, :tenants
    add_index :usage_events, [:tenant_id, :idempotency_key], unique: true
    add_index :usage_events, [:tenant_id, :billing_feature_id, :occurred_at], name: "idx_usage_events_tenant_feature_time"
    add_check_constraint :usage_events, "quantity > 0", name: "usage_events_quantity_check"

    create_table :usage_totals, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.references :billing_feature, type: :uuid, null: false, foreign_key: true
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.decimal :quantity, precision: 20, scale: 6, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :usage_totals, :tenants
    add_index :usage_totals, [:tenant_id, :billing_feature_id, :period_start, :period_end], unique: true, name: "idx_usage_totals_scope_period"
    add_check_constraint :usage_totals, "period_end > period_start", name: "usage_totals_period_check"
    add_check_constraint :usage_totals, "quantity >= 0", name: "usage_totals_quantity_check"

    create_table :billing_events, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.string :event_type, null: false
      t.uuid :actor_user_id
      t.uuid :subject_id
      t.string :subject_type
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end
    add_foreign_key :billing_events, :tenants
    add_foreign_key :billing_events, :users, column: :actor_user_id
    add_index :billing_events, [:tenant_id, :occurred_at]
    add_index :billing_events, [:tenant_id, :event_type, :occurred_at], name: "idx_billing_events_type_time"

    execute "GRANT SELECT ON billing_plans, billing_prices, billing_features, billing_entitlements TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON subscriptions, invoices, usage_totals TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON usage_events, billing_events TO crystell_runtime"

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

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_billing_event_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'billing_events are append-only';
      END;
      $$
    SQL
    execute <<~SQL
      CREATE TRIGGER billing_events_append_only
      BEFORE UPDATE OR DELETE ON billing_events
      FOR EACH ROW EXECUTE FUNCTION crystell.prevent_billing_event_mutation()
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS billing_events_append_only ON billing_events"
    execute "DROP FUNCTION IF EXISTS crystell.prevent_billing_event_mutation()"
    drop_table :billing_events
    drop_table :usage_totals
    drop_table :usage_events
    drop_table :invoices
    drop_table :subscriptions
    drop_table :billing_entitlements
    drop_table :billing_features
    drop_table :billing_prices
    drop_table :billing_plans
  end
end
