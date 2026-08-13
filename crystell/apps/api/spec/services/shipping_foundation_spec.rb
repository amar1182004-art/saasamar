require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Shipping foundation" do
  let(:password) { "Crystell-Shipping-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @registration = Auth::AccountRegistration.call(
      email: "shipping-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Shipping Tenant #{unique}",
      tenant_slug: "shipping-tenant-#{unique}",
      store_name: "Shipping Store #{unique}",
      store_slug: "shipping-store-#{unique}"
    )
    @owner = IdentityScope.with(@registration.user_id) { User.find(@registration.user_id) }

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      @store = Store.find_by!(slug: "shipping-store-#{unique}")
      @store.update!(status: "active")
      product = Catalog::ProductCreator.call(
        store_id: @store.id,
        attributes: { title: "Shipping Product #{unique}", slug: "shipping-product-#{unique}", status: "active", published_at: Time.current },
        variants: [{ title: "Default", sku: "SHIP-#{unique}", currency: "EGP", price_cents: 20_000, track_inventory: true }]
      )
      @variant = product.product_variants.first!
      @location = InventoryLocation.create!(tenant_id: Current.tenant_id, store_id: @store.id, name: "Shipping Warehouse #{unique}", code: "shipping-warehouse-#{unique}", priority: 0)
      Inventory::Adjuster.call(store_id: @store.id, inventory_location_id: @location.id, product_variant_id: @variant.id, delta_on_hand: 3, reason: "stock.received", idempotency_key: "shipping-stock-#{unique}")

      cart = Commerce::CartManager.create(store_id: @store.id)
      Commerce::CartManager.add_item(store_id: @store.id, access_token: cart.access_token, product_variant_id: @variant.id, quantity: 1)
      @checkout = Checkout::SessionCreator.call(store_id: @store.id, cart_access_token: cart.access_token, idempotency_key: "shipping-checkout-#{unique}", customer_email: "buyer-#{unique}@example.test")
      Checkout::InventoryAllocator.call(checkout_session_id: @checkout.id)

      @account = ShippingProviderAccount.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        provider_key: "reference_flat_rate",
        mode: "test",
        display_name: "Reference Shipping",
        credentials: { "base_rate_cents" => 4_000, "per_item_cents" => 750 },
        public_config: {}
      )
    end
  end

  after do
    tenant_id = @registration&.tenant_id
    if tenant_id.present? && @admin
      %w[shipment_events shipments shipping_rate_quotes shipping_provider_accounts].each do |table|
        @admin.exec_params("DELETE FROM #{table} WHERE tenant_id = $1::uuid", [tenant_id])
      end
    end
    @admin&.close
    Current.reset
  end

  it "encrypts credentials, quotes from trusted checkout lines and applies the selected quote" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      account = ShippingProviderAccount.find(@account.id)
      expect(account.credentials_ciphertext).not_to include("base_rate_cents")
      expect(account.credentials.fetch("base_rate_cents")).to eq(4_000)

      quotes = Shipping::RateQuoter.call(
        checkout_session_id: @checkout.id,
        shipping_provider_account_id: account.id,
        destination: { country_code: "EG", city: "Cairo", postal_code: "11511" }
      )
      quote = quotes.first
      expect(quote.amount_cents).to eq(4_750)

      selected = Shipping::QuoteSelector.call(
        checkout_session_id: @checkout.id,
        shipping_rate_quote_id: quote.id,
        shipping_address: { country_code: "EG", city: "Cairo", address1: "Test Street" }
      )
      expect(selected.shipping_cents).to eq(4_750)
      expect(selected.total_cents).to eq(selected.subtotal_cents - selected.discount_cents + 4_750 + selected.tax_cents)
      expect(selected.selected_shipping_rate_quote_id).to eq(quote.id)
    end
  end

  it "creates one idempotent shipment with an append-only creation event" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      quote = Shipping::RateQuoter.call(
        checkout_session_id: @checkout.id,
        shipping_provider_account_id: @account.id,
        destination: { country_code: "EG", city: "Cairo" }
      ).first
      Shipping::QuoteSelector.call(
        checkout_session_id: @checkout.id,
        shipping_rate_quote_id: quote.id,
        shipping_address: { country_code: "EG", city: "Cairo", address1: "Test Street" }
      )
      order = Checkout::OrderPlacer.call(checkout_session_id: @checkout.id)

      first = Shipping::ShipmentCreator.call(order_id: order.id, idempotency_key: "shipment-#{unique}")
      second = Shipping::ShipmentCreator.call(order_id: order.id, idempotency_key: "shipment-#{unique}")

      expect(second.id).to eq(first.id)
      expect(first.status).to eq("label_ready")
      expect(first.tracking_number).to start_with("CRYSTELL")
      expect(ShipmentEvent.where(shipment_id: first.id, event_type: "shipment_created").count).to eq(1)
    end
  end

  it "rejects selecting a quote that belongs to another checkout" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      quote = Shipping::RateQuoter.call(
        checkout_session_id: @checkout.id,
        shipping_provider_account_id: @account.id,
        destination: { country_code: "EG" }
      ).first

      cart = Commerce::CartManager.create(store_id: @store.id)
      Commerce::CartManager.add_item(store_id: @store.id, access_token: cart.access_token, product_variant_id: @variant.id, quantity: 1)
      other_checkout = Checkout::SessionCreator.call(store_id: @store.id, cart_access_token: cart.access_token, idempotency_key: "shipping-other-checkout-#{unique}")

      expect {
        Shipping::QuoteSelector.call(
          checkout_session_id: other_checkout.id,
          shipping_rate_quote_id: quote.id,
          shipping_address: { country_code: "EG" }
        )
      }.to raise_error(Shipping::QuoteSelector::InvalidQuoteError, /another checkout/)
    end
  end
end
