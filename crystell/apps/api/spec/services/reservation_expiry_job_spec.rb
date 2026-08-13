require "rails_helper"
require "securerandom"

RSpec.describe "Reservation expiry job" do
  let(:password) { "Crystell-Expiry-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    registration = Auth::AccountRegistration.call(
      email: "expiry-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Expiry Tenant #{unique}",
      tenant_slug: "expiry-tenant-#{unique}",
      store_name: "Expiry Store #{unique}",
      store_slug: "expiry-store-#{unique}"
    )

    @tenant_id = registration.tenant_id
    @owner = IdentityScope.with(registration.user_id) { User.find(registration.user_id) }

    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      @store = Store.find_by!(slug: "expiry-store-#{unique}")
      product = Catalog::ProductCreator.call(
        store_id: @store.id,
        attributes: { title: "Expiry Product", slug: "expiry-product-#{unique}" },
        variants: [{ title: "Default", currency: "EGP", price_cents: 10_000 }]
      )
      @variant = product.product_variants.first!
      @location = InventoryLocation.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        name: "Expiry Warehouse",
        code: "expiry-warehouse-#{unique}"
      )

      Inventory::Adjuster.call(
        store_id: @store.id,
        inventory_location_id: @location.id,
        product_variant_id: @variant.id,
        delta_on_hand: 2,
        reason: "stock.received",
        idempotency_key: "expiry-stock-#{unique}"
      )

      reservation = Inventory::ReservationManager.reserve(
        store_id: @store.id,
        inventory_location_id: @location.id,
        product_variant_id: @variant.id,
        quantity: 1,
        idempotency_key: "expiry-reservation-#{unique}",
        expires_at: 1.hour.from_now
      )
      @reservation_id = reservation.reservation_id
    end
  end

  after do
    Current.reset
  end

  it "expires a reservation without impersonating a merchant and releases stock exactly once" do
    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      InventoryReservation.find(@reservation_id).update!(expires_at: 1.minute.ago)
      level = InventoryLevel.find_by!(
        inventory_location_id: @location.id,
        product_variant_id: @variant.id
      )
      expect(level.reserved).to eq(1)
      expect(level.available).to eq(1)
    end

    Current.reset
    described_class_name = ExpireInventoryReservationJob.name
    expect(described_class_name).to eq("ExpireInventoryReservationJob")

    ExpireInventoryReservationJob.new.perform(@tenant_id, @reservation_id)
    expect(Current.user).to be_nil
    expect(Current.membership).to be_nil
    expect(Current.tenant_id).to be_nil

    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      reservation = InventoryReservation.find(@reservation_id)
      level = InventoryLevel.find_by!(
        inventory_location_id: @location.id,
        product_variant_id: @variant.id
      )

      expect(reservation.status).to eq("expired")
      expect(level.on_hand).to eq(2)
      expect(level.reserved).to eq(0)
      expect(level.available).to eq(2)
      expect(
        InventoryLedgerEntry.where(
          reference_type: "InventoryReservation",
          reference_id: @reservation_id,
          reason: "reservation.expired"
        ).count
      ).to eq(1)
    end

    ExpireInventoryReservationJob.new.perform(@tenant_id, @reservation_id)

    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      expect(
        InventoryLedgerEntry.where(
          reference_type: "InventoryReservation",
          reference_id: @reservation_id,
          reason: "reservation.expired"
        ).count
      ).to eq(1)
      expect(InventoryLevel.find_by!(product_variant_id: @variant.id).reserved).to eq(0)
    end
  end
end
