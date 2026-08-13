require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Shipping event immutability" do
  let(:password) { "Crystell-Shipping-Immutability-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @registration = Auth::AccountRegistration.call(
      email: "shipping-immutability-#{unique}@example.test",
      password: password,
      tenant_name: "Shipping Immutability #{unique}",
      tenant_slug: "shipping-immutability-#{unique}",
      store_name: "Shipping Immutability Store #{unique}",
      store_slug: "shipping-immutability-store-#{unique}"
    )
    @owner = IdentityScope.with(@registration.user_id) { User.find(@registration.user_id) }

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      @store = Store.find_by!(slug: "shipping-immutability-store-#{unique}")
      @store.update!(status: "active")

      product = Catalog::ProductCreator.call(
        store_id: @store.id,
        attributes: { title: "Product #{unique}", slug: "shipping-immutability-product-#{unique}", status: "active", published_at: Time.current },
        variants: [{ title: "Default", sku: "SHIP-IMM-#{unique}", currency: "EGP", price_cents: 10_000, track_inventory: true }]
      )
      variant = product.product_variants.first!
      location = InventoryLocation.create!(tenant_id: Current.tenant_id, store_id: @store.id, name: "Warehouse #{unique}", code: "shipping-immutability-warehouse-#{unique}", priority: 0)
      Inventory::Adjuster.call(store_id: @store.id, inventory_location_id: location.id, product_variant_id: variant.id, delta_on_hand: 1, reason: "stock.received", idempotency_key: "shipping-immutability-stock-#{unique}")

      cart = Commerce::CartManager.create(store_id: @store.id)
      Commerce::CartManager.add_item(store_id: @store.id, access_token: cart.access_token, product_variant_id: variant.id, quantity: 1)
      checkout = Checkout::SessionCreator.call(store_id: @store.id, cart_access_token: cart.access_token, idempotency_key: "shipping-immutability-checkout-#{unique}")
      Checkout::InventoryAllocator.call(checkout_session_id: checkout.id)

      account = ShippingProviderAccount.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        provider_key: "reference_flat_rate",
        mode: "test",
        display_name: "Reference Shipping",
        credentials: { "base_rate_cents" => 1_000 },
        public_config: {}
      )
      quote = Shipping::RateQuoter.call(
        checkout_session_id: checkout.id,
        shipping_provider_account_id: account.id,
        destination: { country_code: "EG", city: "Cairo" }
      ).first
      Shipping::QuoteSelector.call(
        checkout_session_id: checkout.id,
        shipping_rate_quote_id: quote.id,
        shipping_address: { country_code: "EG", city: "Cairo", address1: "Test Street" }
      )
      order = Checkout::OrderPlacer.call(checkout_session_id: checkout.id)
      shipment = Shipping::ShipmentCreator.call(order_id: order.id, idempotency_key: "shipping-immutability-shipment-#{unique}")
      @event_id = ShipmentEvent.find_by!(shipment_id: shipment.id, event_type: "shipment_created").id
    end
  end

  after do
    tenant_id = @registration&.tenant_id
    if tenant_id.present? && @admin
      @admin.exec_params("UPDATE checkout_sessions SET selected_shipping_rate_quote_id = NULL WHERE tenant_id = $1::uuid", [tenant_id])
      %w[shipment_events shipments shipping_rate_quotes shipping_provider_accounts].each do |table|
        @admin.exec_params("DELETE FROM #{table} WHERE tenant_id = $1::uuid", [tenant_id])
      end
    end
    @admin&.close
    Current.reset
  end

  it "blocks runtime mutation while allowing maintenance mutation" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      expect {
        ShipmentEvent.transaction(requires_new: true) do
          ShipmentEvent.find(@event_id).update!(message: "runtime mutation")
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /shipment_events_are_append_only/)
    end

    @admin.exec_params("UPDATE shipment_events SET message = $1 WHERE id = $2::uuid", ["maintenance mutation", @event_id])

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      expect(ShipmentEvent.find(@event_id).message).to eq("maintenance mutation")
    end
  end
end
