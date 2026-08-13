require "rails_helper"
require "pg"
require "securerandom"
require "openssl"
require "json"

RSpec.describe "Payment foundation" do
  let(:password) { "Crystell-Payment-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }
  let(:webhook_secret) { "webhook-secret-#{unique}" }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @registration = Auth::AccountRegistration.call(
      email: "payment-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Payment Tenant #{unique}",
      tenant_slug: "payment-tenant-#{unique}",
      store_name: "Payment Store #{unique}",
      store_slug: "payment-store-#{unique}"
    )
    @owner = IdentityScope.with(@registration.user_id) { User.find(@registration.user_id) }

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      @store = Store.find_by!(slug: "payment-store-#{unique}")
      @store.update!(status: "active")
      product = Catalog::ProductCreator.call(
        store_id: @store.id,
        attributes: {
          title: "Payment Product #{unique}",
          slug: "payment-product-#{unique}",
          status: "active",
          published_at: Time.current
        },
        variants: [{
          title: "Default",
          sku: "PAYMENT-#{unique}",
          currency: "EGP",
          price_cents: 15_000,
          track_inventory: true
        }]
      )
      @variant = product.product_variants.first!
      @location = InventoryLocation.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        name: "Payment Warehouse #{unique}",
        code: "payment-warehouse-#{unique}",
        priority: 0
      )
      Inventory::Adjuster.call(
        store_id: @store.id,
        inventory_location_id: @location.id,
        product_variant_id: @variant.id,
        delta_on_hand: 2,
        reason: "stock.received",
        idempotency_key: "payment-stock-#{unique}"
      )

      cart = Commerce::CartManager.create(store_id: @store.id)
      @cart_token = cart.access_token
      @cart_id = cart.cart.id
      Commerce::CartManager.add_item(
        store_id: @store.id,
        access_token: @cart_token,
        product_variant_id: @variant.id,
        quantity: 1
      )
      @checkout = Checkout::SessionCreator.call(
        store_id: @store.id,
        cart_access_token: @cart_token,
        idempotency_key: "payment-checkout-#{unique}",
        customer_email: "buyer-#{unique}@example.test"
      )
      Checkout::InventoryAllocator.call(checkout_session_id: @checkout.id)
      @order = Checkout::OrderPlacer.call(checkout_session_id: @checkout.id)

      @account = PaymentProviderAccount.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        provider_key: "reference_hmac",
        mode: "test",
        display_name: "Reference Test",
        credentials: {
          "api_key" => "api-secret-#{unique}",
          "checkout_base_url" => "https://payments.example.test/checkout"
        },
        webhook_secret: webhook_secret,
        public_config: { "supports_redirect" => true }
      )
    end
  end

  after do
    tenant_id = @registration&.tenant_id
    if tenant_id.present? && @admin
      %w[
        payment_webhook_events
        payment_transactions
        payment_intents
        payment_provider_accounts
        checkout_inventory_reservations
        order_items
        orders
        store_order_sequences
        checkout_line_items
        checkout_sessions
        cart_items
        carts
      ].each do |table|
        @admin.exec_params("DELETE FROM #{table} WHERE tenant_id = $1::uuid", [tenant_id])
      end
    end
    @admin&.close
    Current.reset
  end

  it "encrypts provider secrets at rest and restores them only through the credential vault" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      account = PaymentProviderAccount.find(@account.id)
      expect(account.credentials_ciphertext).not_to include("api-secret-#{unique}")
      expect(account.webhook_secret_ciphertext).not_to include(webhook_secret)
      expect(account.credentials.fetch("api_key")).to eq("api-secret-#{unique}")
      expect(account.webhook_secret).to eq(webhook_secret)
    end
  end

  it "places one immutable order and creates one idempotent provider payment intent" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      replayed_order = Checkout::OrderPlacer.call(checkout_session_id: @checkout.id)
      expect(replayed_order.id).to eq(@order.id)
      expect(replayed_order.order_items.first.unit_price_cents).to eq(15_000)

      first = Payment::IntentCreator.call(
        order_id: @order.id,
        payment_provider_account_id: @account.id,
        idempotency_key: "payment-intent-#{unique}"
      )
      second = Payment::IntentCreator.call(
        order_id: @order.id,
        payment_provider_account_id: @account.id,
        idempotency_key: "payment-intent-#{unique}"
      )
      expect(second.id).to eq(first.id)

      dispatched = Payment::IntentDispatcher.call(payment_intent_id: first.id)
      expect(dispatched.status).to eq("requires_action")
      expect(dispatched.provider_intent_id).to start_with("ref_")
      expect(dispatched.checkout_url).to include(dispatched.provider_intent_id)
      expect(@order.reload.payment_status).to eq("pending")
    end
  end

  it "verifies a webhook, settles the order, consumes inventory and ignores exact replays" do
    payment_intent = nil
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      payment_intent = Payment::IntentCreator.call(
        order_id: @order.id,
        payment_provider_account_id: @account.id,
        idempotency_key: "settlement-#{unique}"
      )
      payment_intent = Payment::IntentDispatcher.call(payment_intent_id: payment_intent.id)
    end

    raw_body = JSON.generate(
      "event_id" => "evt_#{unique}",
      "event_type" => "payment.succeeded",
      "payment_intent_id" => payment_intent.provider_intent_id,
      "status" => "paid",
      "amount_cents" => payment_intent.amount_cents,
      "currency" => payment_intent.currency,
      "transaction_id" => "txn_#{unique}",
      "metadata" => {}
    )
    signature = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, raw_body)

    first = Payment::WebhookReceiver.call(
      endpoint_id: @account.webhook_endpoint_id,
      raw_body: raw_body,
      headers: { "X-Crystell-Signature" => signature }
    )
    second = Payment::WebhookReceiver.call(
      endpoint_id: @account.webhook_endpoint_id,
      raw_body: raw_body,
      headers: { "X-Crystell-Signature" => signature }
    )

    expect(first.event.status).to eq("processed")
    expect(first.duplicate).to be(false)
    expect(second.duplicate).to be(true)

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      expect(payment_intent.reload.status).to eq("paid")
      expect(@order.reload.payment_status).to eq("paid")
      expect(@order.status).to eq("confirmed")
      expect(@checkout.reload.status).to eq("completed")
      expect(Cart.find(@cart_id).status).to eq("converted")

      reservation_ids = CheckoutInventoryReservation.where(checkout_session_id: @checkout.id).pluck(:inventory_reservation_id)
      expect(InventoryReservation.where(id: reservation_ids).pluck(:status).uniq).to eq(["consumed"])
      level = InventoryLevel.find_by!(inventory_location_id: @location.id, product_variant_id: @variant.id)
      expect(level.on_hand).to eq(1)
      expect(level.reserved).to eq(0)
      expect(level.available).to eq(1)
      expect(PaymentTransaction.where(payment_intent_id: payment_intent.id, kind: "capture").count).to eq(1)
      expect(PaymentWebhookEvent.where(payment_provider_account_id: @account.id, provider_event_id: "evt_#{unique}").count).to eq(1)
    end
  end

  it "rejects invalid webhook signatures before persisting an event" do
    before_count = nil
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      before_count = PaymentWebhookEvent.where(payment_provider_account_id: @account.id).count
    end

    raw_body = JSON.generate(
      "event_id" => "invalid-signature-#{unique}",
      "event_type" => "payment.failed",
      "payment_intent_id" => "unknown",
      "status" => "failed",
      "amount_cents" => 15_000,
      "currency" => "EGP"
    )

    expect do
      Payment::WebhookReceiver.call(
        endpoint_id: @account.webhook_endpoint_id,
        raw_body: raw_body,
        headers: { "X-Crystell-Signature" => "not-a-valid-signature" }
      )
    end.to raise_error(Payment::Adapters::ReferenceHmac::InvalidSignatureError)

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      expect(PaymentWebhookEvent.where(payment_provider_account_id: @account.id).count).to eq(before_count)
    end
  end

  it "keeps payment transactions append-only for the runtime role" do
    payment_intent = nil
    transaction = nil

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      payment_intent = Payment::IntentCreator.call(
        order_id: @order.id,
        payment_provider_account_id: @account.id,
        idempotency_key: "append-only-#{unique}"
      )
      transaction = PaymentTransaction.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        payment_intent_id: payment_intent.id,
        kind: "authorization",
        status: "succeeded",
        currency: payment_intent.currency,
        amount_cents: payment_intent.amount_cents,
        idempotency_key: "append-only-transaction-#{unique}"
      )

      expect do
        ApplicationRecord.transaction(requires_new: true) do
          transaction.update!(status: "failed")
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /payment_transactions_are_append_only/)
    end
  end
end
