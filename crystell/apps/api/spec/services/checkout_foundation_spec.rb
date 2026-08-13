require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Checkout foundation" do
  let(:password) { "Crystell-Checkout-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @tenant_a = Auth::AccountRegistration.call(
      email: "checkout-owner-a-#{unique}@example.test",
      password: password,
      tenant_name: "Checkout Tenant A #{unique}",
      tenant_slug: "checkout-tenant-a-#{unique}",
      store_name: "Checkout Store A #{unique}",
      store_slug: "checkout-store-a-#{unique}"
    )
    @tenant_b = Auth::AccountRegistration.call(
      email: "checkout-owner-b-#{unique}@example.test",
      password: password,
      tenant_name: "Checkout Tenant B #{unique}",
      tenant_slug: "checkout-tenant-b-#{unique}",
      store_name: "Checkout Store B #{unique}",
      store_slug: "checkout-store-b-#{unique}"
    )
    @owner_a = IdentityScope.with(@tenant_a.user_id) { User.find(@tenant_a.user_id) }
    @owner_b = IdentityScope.with(@tenant_b.user_id) { User.find(@tenant_b.user_id) }

    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      @store_a = Store.find_by!(slug: "checkout-store-a-#{unique}")
      @store_a.update!(status: "active")
      @product_a, @variant_a = create_product!(store: @store_a, suffix: "a", price_cents: 12_500)
    end
    TenantAccess.with(user: @owner_b, tenant_id: @tenant_b.tenant_id) do
      @store_b = Store.find_by!(slug: "checkout-store-b-#{unique}")
      @store_b.update!(status: "active")
      @product_b, @variant_b = create_product!(store: @store_b, suffix: "b", price_cents: 99_900)
    end
  end

  after do
    tenant_ids = [@tenant_a&.tenant_id, @tenant_b&.tenant_id].compact
    unless tenant_ids.empty? || @admin.nil?
      placeholders = tenant_ids.each_index.map { |index| "$#{index + 1}::uuid" }.join(", ")
      %w[order_items orders store_order_sequences checkout_line_items checkout_sessions cart_items carts].each do |table|
        @admin.exec_params("DELETE FROM #{table} WHERE tenant_id IN (#{placeholders})", tenant_ids)
      end
    end
    @admin&.close
    Current.reset
  end

  it "stores only a digest of the cart capability token and prices checkout from the catalog" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      created = Commerce::CartManager.create(store_id: @store_a.id)
      expect(created.cart.access_token_digest).not_to eq(created.access_token)
      expect(created.cart.access_token_digest.length).to eq(64)

      Commerce::CartManager.add_item(
        store_id: @store_a.id,
        access_token: created.access_token,
        product_variant_id: @variant_a.id,
        quantity: 3
      )

      checkout = Checkout::SessionCreator.call(
        store_id: @store_a.id,
        cart_access_token: created.access_token,
        idempotency_key: "checkout-#{unique}",
        customer_email: "buyer-#{unique}@example.test"
      )
      line = checkout.checkout_line_items.first

      expect(line.unit_price_cents).to eq(12_500)
      expect(line.quantity).to eq(3)
      expect(line.line_subtotal_cents).to eq(37_500)
      expect(checkout.subtotal_cents).to eq(37_500)
      expect(checkout.total_cents).to eq(37_500)
      expect(created.cart.reload.status).to eq("checking_out")
    end
  end

  it "freezes the checkout price snapshot even if the catalog changes afterward" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      created = Commerce::CartManager.create(store_id: @store_a.id)
      Commerce::CartManager.add_item(store_id: @store_a.id, access_token: created.access_token, product_variant_id: @variant_a.id, quantity: 1)
      checkout = Checkout::SessionCreator.call(store_id: @store_a.id, cart_access_token: created.access_token, idempotency_key: "freeze-#{unique}")

      @variant_a.update!(price_cents: 77_700)
      expect(checkout.checkout_line_items.first.reload.unit_price_cents).to eq(12_500)
      expect(checkout.reload.total_cents).to eq(12_500)
    end
  end

  it "returns the same checkout for an exact idempotent replay" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      created = Commerce::CartManager.create(store_id: @store_a.id)
      Commerce::CartManager.add_item(store_id: @store_a.id, access_token: created.access_token, product_variant_id: @variant_a.id, quantity: 2)
      first = Checkout::SessionCreator.call(store_id: @store_a.id, cart_access_token: created.access_token, idempotency_key: "same-#{unique}")
      second = Checkout::SessionCreator.call(store_id: @store_a.id, cart_access_token: created.access_token, idempotency_key: "same-#{unique}")

      expect(second.id).to eq(first.id)
      expect(CheckoutSession.where(idempotency_key: "same-#{unique}").count).to eq(1)
    end
  end

  it "persists cart expiry even though the caller receives an error" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      created = Commerce::CartManager.create(store_id: @store_a.id, expires_at: 1.minute.ago)

      expect do
        Commerce::CartManager.add_item(
          store_id: @store_a.id,
          access_token: created.access_token,
          product_variant_id: @variant_a.id,
          quantity: 1
        )
      end.to raise_error(Commerce::CartManager::InvalidCartError, /expired/)

      expect(Cart.find(created.cart.id).status).to eq("expired")
    end
  end

  it "refuses cart creation while the store is not active" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      @store_a.update!(status: "draft")

      expect do
        Commerce::CartManager.create(store_id: @store_a.id)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "rejects cross-store or cross-tenant variant injection" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      created = Commerce::CartManager.create(store_id: @store_a.id)
      expect do
        Commerce::CartManager.add_item(
          store_id: @store_a.id,
          access_token: created.access_token,
          product_variant_id: @variant_b.id,
          quantity: 1
        )
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "enforces checkout totals at PostgreSQL" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      created = Commerce::CartManager.create(store_id: @store_a.id)
      Commerce::CartManager.add_item(store_id: @store_a.id, access_token: created.access_token, product_variant_id: @variant_a.id, quantity: 1)

      expect do
        CheckoutSession.create!(
          tenant_id: Current.tenant_id,
          store_id: @store_a.id,
          cart_id: created.cart.id,
          status: "open",
          currency: "EGP",
          subtotal_cents: 100,
          discount_cents: 0,
          shipping_cents: 0,
          tax_cents: 0,
          total_cents: 1,
          idempotency_key: "invalid-total-#{unique}",
          priced_at: Time.current,
          expires_at: 30.minutes.from_now
        )
      end.to raise_error(ActiveRecord::StatementInvalid, /checkout_total_formula_check/)
    end
  end

  private

  def create_product!(store:, suffix:, price_cents:)
    product = Catalog::ProductCreator.call(
      store_id: store.id,
      attributes: {
        title: "Checkout Product #{suffix} #{unique}",
        slug: "checkout-product-#{suffix}-#{unique}",
        status: "active",
        published_at: Time.current
      },
      variants: [{ title: "Default", sku: "CHECKOUT-#{suffix}-#{unique}", currency: "EGP", price_cents: price_cents }]
    )
    [product, product.product_variants.first]
  end
end
