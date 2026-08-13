class AddCouponsAndAffiliates < ActiveRecord::Migration[8.0]
  TENANT_TABLES = %w[billing_coupon_redemptions billing_affiliate_attributions billing_commissions].freeze

  def up
    create_table :billing_coupons, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.citext :code, null: false
      t.string :discount_type, null: false
      t.integer :percentage_basis_points
      t.bigint :fixed_amount_cents
      t.string :currency
      t.string :status, null: false, default: "active"
      t.references :billing_plan, type: :uuid, null: true, foreign_key: true
      t.integer :max_redemptions
      t.integer :per_tenant_limit, null: false, default: 1
      t.datetime :starts_at
      t.datetime :ends_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :billing_coupons, :code, unique: true
    add_check_constraint :billing_coupons, "discount_type IN ('percentage', 'fixed')", name: "billing_coupons_type_check"
    add_check_constraint :billing_coupons, "status IN ('active', 'disabled', 'expired')", name: "billing_coupons_status_check"
    add_check_constraint :billing_coupons, "per_tenant_limit > 0", name: "billing_coupons_tenant_limit_check"
    add_check_constraint :billing_coupons, "max_redemptions IS NULL OR max_redemptions > 0", name: "billing_coupons_max_redemptions_check"
    add_check_constraint :billing_coupons,
                         "(discount_type = 'percentage' AND percentage_basis_points BETWEEN 1 AND 10000 AND fixed_amount_cents IS NULL) OR (discount_type = 'fixed' AND fixed_amount_cents > 0 AND percentage_basis_points IS NULL AND currency IS NOT NULL)",
                         name: "billing_coupons_value_check"
    add_check_constraint :billing_coupons, "currency IS NULL OR (currency = upper(currency) AND char_length(currency) = 3)", name: "billing_coupons_currency_check"
    add_check_constraint :billing_coupons, "ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at", name: "billing_coupons_window_check"

    create_table :billing_coupon_redemptions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.references :billing_coupon, type: :uuid, null: false, foreign_key: true
      t.references :subscription, type: :uuid, null: false, foreign_key: true
      t.references :invoice, type: :uuid, null: true, foreign_key: true
      t.string :idempotency_key, null: false
      t.bigint :discount_cents, null: false
      t.datetime :redeemed_at, null: false
      t.timestamps
    end
    add_foreign_key :billing_coupon_redemptions, :tenants
    add_index :billing_coupon_redemptions, [:tenant_id, :idempotency_key], unique: true, name: "idx_coupon_redemptions_idempotency"
    add_index :billing_coupon_redemptions, [:tenant_id, :billing_coupon_id, :redeemed_at], name: "idx_coupon_redemptions_tenant_coupon"
    add_check_constraint :billing_coupon_redemptions, "discount_cents >= 0", name: "billing_coupon_redemptions_amount_check"

    create_table :billing_affiliates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :display_name, null: false
      t.citext :email
      t.string :status, null: false, default: "active"
      t.string :commission_type, null: false
      t.integer :percentage_basis_points
      t.bigint :fixed_amount_cents
      t.string :currency
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_check_constraint :billing_affiliates, "status IN ('active', 'paused', 'closed')", name: "billing_affiliates_status_check"
    add_check_constraint :billing_affiliates, "commission_type IN ('percentage', 'fixed')", name: "billing_affiliates_type_check"
    add_check_constraint :billing_affiliates,
                         "(commission_type = 'percentage' AND percentage_basis_points BETWEEN 1 AND 10000 AND fixed_amount_cents IS NULL) OR (commission_type = 'fixed' AND fixed_amount_cents > 0 AND percentage_basis_points IS NULL AND currency IS NOT NULL)",
                         name: "billing_affiliates_value_check"
    add_check_constraint :billing_affiliates, "currency IS NULL OR (currency = upper(currency) AND char_length(currency) = 3)", name: "billing_affiliates_currency_check"

    create_table :billing_affiliate_codes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :billing_affiliate, type: :uuid, null: false, foreign_key: true
      t.citext :code, null: false
      t.string :status, null: false, default: "active"
      t.datetime :starts_at
      t.datetime :ends_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :billing_affiliate_codes, :code, unique: true
    add_check_constraint :billing_affiliate_codes, "status IN ('active', 'disabled', 'expired')", name: "billing_affiliate_codes_status_check"
    add_check_constraint :billing_affiliate_codes, "ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at", name: "billing_affiliate_codes_window_check"

    create_table :billing_affiliate_attributions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.references :billing_affiliate_code, type: :uuid, null: false, foreign_key: true
      t.references :converted_subscription, type: :uuid, null: true, foreign_key: { to_table: :subscriptions }
      t.string :status, null: false, default: "active"
      t.datetime :attributed_at, null: false
      t.datetime :expires_at
      t.datetime :converted_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :billing_affiliate_attributions, :tenants
    add_index :billing_affiliate_attributions, :tenant_id, unique: true, where: "status = 'active'", name: "idx_affiliate_attributions_one_active"
    add_index :billing_affiliate_attributions, [:tenant_id, :billing_affiliate_code_id]
    add_check_constraint :billing_affiliate_attributions, "status IN ('active', 'converted', 'expired', 'void')", name: "billing_affiliate_attributions_status_check"

    create_table :billing_commissions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.references :billing_affiliate, type: :uuid, null: false, foreign_key: true
      t.references :billing_affiliate_attribution, type: :uuid, null: false, foreign_key: true
      t.references :invoice, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string :currency, null: false
      t.bigint :basis_cents, null: false
      t.bigint :amount_cents, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :earned_at, null: false
      t.datetime :approved_at
      t.datetime :paid_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_foreign_key :billing_commissions, :tenants
    add_index :billing_commissions, [:billing_affiliate_id, :status, :earned_at], name: "idx_billing_commissions_affiliate_state"
    add_check_constraint :billing_commissions, "currency = upper(currency) AND char_length(currency) = 3", name: "billing_commissions_currency_check"
    add_check_constraint :billing_commissions, "basis_cents >= 0 AND amount_cents >= 0", name: "billing_commissions_amount_check"
    add_check_constraint :billing_commissions, "status IN ('pending', 'approved', 'paid', 'void')", name: "billing_commissions_status_check"

    execute "GRANT SELECT ON billing_coupons, billing_affiliates, billing_affiliate_codes TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON billing_coupon_redemptions, billing_affiliate_attributions, billing_commissions TO crystell_runtime"

    TENANT_TABLES.each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
      execute <<~SQL
        CREATE POLICY tenant_runtime_isolation ON #{table}
        FOR ALL TO crystell_runtime
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
      CREATE OR REPLACE FUNCTION crystell.prevent_billing_append_only_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION '% is append-only', TG_TABLE_NAME;
      END;
      $$
    SQL

    %w[billing_coupon_redemptions billing_commissions].each do |table|
      execute <<~SQL
        CREATE TRIGGER #{table}_append_only
        BEFORE UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION crystell.prevent_billing_append_only_mutation()
      SQL
    end
  end

  def down
    %w[billing_coupon_redemptions billing_commissions].each do |table|
      execute "DROP TRIGGER IF EXISTS #{table}_append_only ON #{table}"
    end
    execute "DROP FUNCTION IF EXISTS crystell.prevent_billing_append_only_mutation()"
    drop_table :billing_commissions
    drop_table :billing_affiliate_attributions
    drop_table :billing_affiliate_codes
    drop_table :billing_affiliates
    drop_table :billing_coupon_redemptions
    drop_table :billing_coupons
  end
end
