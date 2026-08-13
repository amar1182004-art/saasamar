require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Billing foundation" do
  let(:password) { "Crystell-Billing-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))

    @tenant_a = Auth::AccountRegistration.call(
      email: "billing-owner-a-#{unique}@example.test",
      password: password,
      tenant_name: "Billing Tenant A #{unique}",
      tenant_slug: "billing-tenant-a-#{unique}",
      store_name: "Billing Store A #{unique}",
      store_slug: "billing-store-a-#{unique}"
    )
    @tenant_b = Auth::AccountRegistration.call(
      email: "billing-owner-b-#{unique}@example.test",
      password: password,
      tenant_name: "Billing Tenant B #{unique}",
      tenant_slug: "billing-tenant-b-#{unique}",
      store_name: "Billing Store B #{unique}",
      store_slug: "billing-store-b-#{unique}"
    )

    @plan_id = SecureRandom.uuid
    @price_id = SecureRandom.uuid
    @feature_id = SecureRandom.uuid
    @plan_code = "billing-test-#{unique}"
    @feature_key = "products.limit.#{unique}"

    @admin.exec_params(
      <<~SQL,
        INSERT INTO billing_plans (id, code, name, status, position, trial_days, public, metadata, created_at, updated_at)
        VALUES ($1::uuid, $2, $3, 'active', 1, 0, false, '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      [@plan_id, @plan_code, "Billing Test Plan #{unique}"]
    )
    @admin.exec_params(
      <<~SQL,
        INSERT INTO billing_prices (id, billing_plan_id, currency, interval, amount_cents, status, created_at, updated_at)
        VALUES ($1::uuid, $2::uuid, 'EGP', 'monthly', 10000, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      [@price_id, @plan_id]
    )
    @admin.exec_params(
      <<~SQL,
        INSERT INTO billing_features (id, key, name, value_type, unit, metadata, created_at, updated_at)
        VALUES ($1::uuid, $2, $3, 'integer', 'products', '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      [@feature_id, @feature_key, "Products limit #{unique}"]
    )
    @admin.exec_params(
      <<~SQL,
        INSERT INTO billing_entitlements (id, billing_plan_id, billing_feature_id, value, created_at, updated_at)
        VALUES (gen_random_uuid(), $1::uuid, $2::uuid, '{"limit": 100}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      [@plan_id, @feature_id]
    )

    @owner_a = IdentityScope.with(@tenant_a.user_id) { User.find(@tenant_a.user_id) }
    @owner_b = IdentityScope.with(@tenant_b.user_id) { User.find(@tenant_b.user_id) }
  end

  after do
    if @admin
      tenant_ids = [@tenant_a&.tenant_id, @tenant_b&.tenant_id].compact
      unless tenant_ids.empty?
        placeholders = tenant_ids.each_index.map { |index| "$#{index + 1}::uuid" }.join(", ")
        %w[billing_events usage_totals usage_events invoices subscriptions].each do |table|
          @admin.exec_params("DELETE FROM #{table} WHERE tenant_id IN (#{placeholders})", tenant_ids)
        end
      end

      @admin.exec_params("DELETE FROM billing_entitlements WHERE billing_plan_id = $1::uuid", [@plan_id]) if @plan_id
      @admin.exec_params("DELETE FROM billing_prices WHERE billing_plan_id = $1::uuid", [@plan_id]) if @plan_id
      @admin.exec_params("DELETE FROM billing_features WHERE id = $1::uuid", [@feature_id]) if @feature_id
      @admin.exec_params("DELETE FROM billing_plans WHERE id = $1::uuid", [@plan_id]) if @plan_id
      @admin.close
    end
    Current.reset
  end

  it "provisions tenant subscriptions, resolves entitlements and meters usage idempotently" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do |membership|
      expect(membership.role).to eq("owner")

      subscription = Billing::SubscriptionProvisioner.call(price_id: @price_id)
      expect(subscription.status).to eq("active")

      entitlement = Billing::EntitlementResolver.call(feature_key: @feature_key)
      expect(entitlement.plan_code).to eq(@plan_code)
      expect(entitlement.limit).to eq(100)

      first = Billing::UsageMeter.call(
        feature_key: @feature_key,
        quantity: 3,
        idempotency_key: "usage-#{unique}"
      )
      duplicate = Billing::UsageMeter.call(
        feature_key: @feature_key,
        quantity: 3,
        idempotency_key: "usage-#{unique}"
      )

      expect(first.recorded).to be(true)
      expect(first.total_quantity).to eq(3)
      expect(duplicate.recorded).to be(false)
      expect(duplicate.total_quantity).to eq(3)
      expect(UsageEvent.where(billing_feature_id: @feature_id).count).to eq(1)
      expect(UsageTotal.find_by!(billing_feature_id: @feature_id).quantity).to eq(3)
    end
  end

  it "isolates subscription data and rejects cross-tenant billing writes at PostgreSQL" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      Billing::SubscriptionProvisioner.call(price_id: @price_id)
    end
    TenantAccess.with(user: @owner_b, tenant_id: @tenant_b.tenant_id) do
      Billing::SubscriptionProvisioner.call(price_id: @price_id)
    end

    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      expect(Subscription.pluck(:tenant_id)).to contain_exactly(@tenant_a.tenant_id)

      connection = ApplicationRecord.connection
      expect do
        connection.execute(<<~SQL)
          INSERT INTO invoices (
            id, tenant_id, number, status, currency,
            subtotal_cents, discount_cents, tax_cents, total_cents, amount_paid_cents,
            metadata, created_at, updated_at
          ) VALUES (
            gen_random_uuid(),
            #{connection.quote(@tenant_b.tenant_id)},
            #{connection.quote("forbidden-#{unique}")},
            'draft', 'EGP', 0, 0, 0, 0, 0, '{}'::jsonb,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          )
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /row-level security|policy/i)
    end
  end

  it "does not allow the merchant runtime role to mutate the global plan catalog" do
    expect do
      BillingPlan.create!(code: "forbidden-#{unique}", name: "Forbidden", status: "active")
    end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
  end
end
