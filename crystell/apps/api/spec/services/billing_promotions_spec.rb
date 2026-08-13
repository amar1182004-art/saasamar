require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Billing promotions and affiliates" do
  let(:password) { "Crystell-Promotions-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))

    @registration = Auth::AccountRegistration.call(
      email: "promotions-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Promotions Tenant #{unique}",
      tenant_slug: "promotions-tenant-#{unique}",
      store_name: "Promotions Store #{unique}",
      store_slug: "promotions-store-#{unique}"
    )
    @second_registration = Auth::AccountRegistration.call(
      email: "promotions-second-#{unique}@example.test",
      password: password,
      tenant_name: "Promotions Second Tenant #{unique}",
      tenant_slug: "promotions-second-tenant-#{unique}",
      store_name: "Promotions Second Store #{unique}",
      store_slug: "promotions-second-store-#{unique}"
    )

    @owner = IdentityScope.with(@registration.user_id) { User.find(@registration.user_id) }
    @second_owner = IdentityScope.with(@second_registration.user_id) { User.find(@second_registration.user_id) }

    @plan_id = SecureRandom.uuid
    @price_id = SecureRandom.uuid
    @coupon_id = SecureRandom.uuid
    @affiliate_id = SecureRandom.uuid
    @affiliate_code_id = SecureRandom.uuid
    @plan_code = "promo-plan-#{unique}"
    @coupon_code = "SAVE10-#{unique}"
    @affiliate_code = "BLOGGER-#{unique}"

    @admin.exec_params(
      <<~SQL,
        INSERT INTO billing_plans (id, code, name, status, trial_days, public, metadata, created_at, updated_at)
        VALUES ($1::uuid, $2, $3, 'active', 0, false, '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      [@plan_id, @plan_code, "Promotions Plan #{unique}"]
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
        INSERT INTO billing_coupons (
          id, code, discount_type, percentage_basis_points, status, billing_plan_id,
          max_redemptions, per_tenant_limit, metadata, created_at, updated_at
        ) VALUES (
          $1::uuid, $2, 'percentage', 1000, 'active', $3::uuid,
          1, 1, '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
      SQL
      [@coupon_id, @coupon_code, @plan_id]
    )
    @admin.exec_params(
      <<~SQL,
        INSERT INTO billing_affiliates (
          id, display_name, status, commission_type, percentage_basis_points,
          metadata, created_at, updated_at
        ) VALUES (
          $1::uuid, $2, 'active', 'percentage', 2000,
          '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
      SQL
      [@affiliate_id, "Promotions Affiliate #{unique}"]
    )
    @admin.exec_params(
      <<~SQL,
        INSERT INTO billing_affiliate_codes (
          id, billing_affiliate_id, code, status, metadata, created_at, updated_at
        ) VALUES (
          $1::uuid, $2::uuid, $3, 'active', '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
      SQL
      [@affiliate_code_id, @affiliate_id, @affiliate_code]
    )
  end

  after do
    if @admin
      tenant_ids = [@registration&.tenant_id, @second_registration&.tenant_id].compact
      unless tenant_ids.empty?
        placeholders = tenant_ids.each_index.map { |index| "$#{index + 1}::uuid" }.join(", ")
        %w[
          billing_commissions
          billing_affiliate_attributions
          billing_coupon_redemptions
          billing_events
          invoices
          subscriptions
        ].each do |table|
          @admin.exec_params("DELETE FROM #{table} WHERE tenant_id IN (#{placeholders})", tenant_ids)
        end
      end

      @admin.exec_params("DELETE FROM billing_affiliate_codes WHERE id = $1::uuid", [@affiliate_code_id]) if @affiliate_code_id
      @admin.exec_params("DELETE FROM billing_affiliates WHERE id = $1::uuid", [@affiliate_id]) if @affiliate_id
      @admin.exec_params("DELETE FROM billing_coupons WHERE id = $1::uuid", [@coupon_id]) if @coupon_id
      @admin.exec_params("DELETE FROM billing_prices WHERE billing_plan_id = $1::uuid", [@plan_id]) if @plan_id
      @admin.exec_params("DELETE FROM billing_plans WHERE id = $1::uuid", [@plan_id]) if @plan_id
      @admin.close
    end
    Current.reset
  end

  it "applies a coupon atomically, makes invoice retries idempotent and creates one affiliate commission" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      subscription = Billing::SubscriptionProvisioner.call(price_id: @price_id)
      attribution = Billing::AffiliateAttributor.call(code: @affiliate_code)
      expect(attribution.affiliate_id).to eq(@affiliate_id)

      invoice_result = Billing::InvoiceIssuer.call(
        subscription_id: subscription.subscription_id,
        coupon_code: @coupon_code
      )
      retried_invoice = Billing::InvoiceIssuer.call(
        subscription_id: subscription.subscription_id,
        coupon_code: @coupon_code
      )

      expect(invoice_result.subtotal_cents).to eq(10_000)
      expect(invoice_result.discount_cents).to eq(1_000)
      expect(invoice_result.total_cents).to eq(9_000)
      expect(retried_invoice.invoice_id).to eq(invoice_result.invoice_id)
      expect(Invoice.where(subscription_id: subscription.subscription_id).count).to eq(1)
      expect(BillingCouponRedemption.where(billing_coupon_id: @coupon_id).count).to eq(1)

      invoice = Invoice.find(invoice_result.invoice_id)
      invoice.update!(
        status: "paid",
        amount_paid_cents: invoice.total_cents,
        paid_at: Time.current
      )

      commission = Billing::CommissionCreator.call(invoice_id: invoice.id)
      duplicate = Billing::CommissionCreator.call(invoice_id: invoice.id)

      expect(commission.affiliate_id).to eq(@affiliate_id)
      expect(commission.amount_cents).to eq(1_800)
      expect(commission.status).to eq("pending")
      expect(duplicate.commission_id).to eq(commission.commission_id)
      expect(BillingCommission.where(invoice_id: invoice.id).count).to eq(1)
      expect(BillingAffiliateAttribution.find(attribution.attribution_id).status).to eq("converted")
    end
  end

  it "enforces the coupon global redemption cap without exposing other tenant redemptions" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      subscription = Billing::SubscriptionProvisioner.call(price_id: @price_id)
      Billing::InvoiceIssuer.call(subscription_id: subscription.subscription_id, coupon_code: @coupon_code)
    end

    TenantAccess.with(user: @second_owner, tenant_id: @second_registration.tenant_id) do
      subscription = Billing::SubscriptionProvisioner.call(price_id: @price_id)

      expect(BillingCouponRedemption.where(billing_coupon_id: @coupon_id).count).to eq(0)
      expect do
        Billing::InvoiceIssuer.call(subscription_id: subscription.subscription_id, coupon_code: @coupon_code)
      end.to raise_error(Billing::CouponQuote::InvalidCouponError, /redemption limit reached/)
    end
  end
end
