require "rails_helper"
require "securerandom"

RSpec.describe "Inventory ledger authority" do
  let(:password) { "Crystell-Ledger-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    registration = Auth::AccountRegistration.call(
      email: "ledger-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Ledger Tenant #{unique}",
      tenant_slug: "ledger-tenant-#{unique}",
      store_name: "Ledger Store #{unique}",
      store_slug: "ledger-store-#{unique}"
    )

    @tenant_id = registration.tenant_id
    @owner = IdentityScope.with(registration.user_id) { User.find(registration.user_id) }

    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      @store = Store.find_by!(slug: "ledger-store-#{unique}")
      @other_store = Store.create!(
        tenant_id: Current.tenant_id,
        name: "Other Ledger Store #{unique}",
        slug: "other-ledger-store-#{unique}"
      )

      product = Catalog::ProductCreator.call(
        store_id: @store.id,
        attributes: { title: "Ledger Product", slug: "ledger-product-#{unique}" },
        variants: [{ title: "Default", currency: "EGP", price_cents: 10_000 }]
      )
      @variant = product.product_variants.first!
      @location = InventoryLocation.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        name: "Main Ledger Warehouse",
        code: "main-ledger-#{unique}"
      )
      @other_location = InventoryLocation.create!(
        tenant_id: Current.tenant_id,
        store_id: @other_store.id,
        name: "Other Ledger Warehouse",
        code: "other-ledger-#{unique}"
      )
    end
  end

  after do
    Current.reset
  end

  it "allows stock changes only through the PostgreSQL ledger function" do
    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      result = Inventory::Adjuster.call(
        store_id: @store.id,
        inventory_location_id: @location.id,
        product_variant_id: @variant.id,
        delta_on_hand: 5,
        reason: "stock.received",
        idempotency_key: "ledger-authority-#{unique}"
      )

      expect(result.recorded).to be(true)
      expect(result.on_hand).to eq(5)
      expect(InventoryLedgerEntry.where(product_variant_id: @variant.id).count).to eq(1)

      level = InventoryLevel.find_by!(product_variant_id: @variant.id, inventory_location_id: @location.id)
      expect do
        ApplicationRecord.transaction(requires_new: true) do
          level.update!(on_hand: 99)
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)

      expect(level.reload.on_hand).to eq(5)
    end
  end

  it "does not allow the runtime role to forge ledger history directly" do
    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      expect do
        ApplicationRecord.transaction(requires_new: true) do
          InventoryLedgerEntry.create!(
            tenant_id: Current.tenant_id,
            store_id: @store.id,
            inventory_location_id: @location.id,
            product_variant_id: @variant.id,
            delta_on_hand: 100,
            delta_reserved: 0,
            reason: "forged",
            idempotency_key: "forged-ledger-#{unique}"
          )
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)

      expect(InventoryLedgerEntry.where(idempotency_key: "forged-ledger-#{unique}")).to be_empty
    end
  end

  it "returns an idempotent replay only for the exact same inventory change" do
    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      first = Inventory::Adjuster.call(
        store_id: @store.id,
        inventory_location_id: @location.id,
        product_variant_id: @variant.id,
        delta_on_hand: 4,
        reason: "stock.received",
        idempotency_key: "strict-idempotency-#{unique}",
        metadata: { "source" => "test" }
      )
      replay = Inventory::Adjuster.call(
        store_id: @store.id,
        inventory_location_id: @location.id,
        product_variant_id: @variant.id,
        delta_on_hand: 4,
        reason: "stock.received",
        idempotency_key: "strict-idempotency-#{unique}",
        metadata: { "source" => "test" }
      )

      expect(first.recorded).to be(true)
      expect(replay.recorded).to be(false)
      expect(replay.on_hand).to eq(4)

      expect do
        Inventory::Adjuster.call(
          store_id: @store.id,
          inventory_location_id: @location.id,
          product_variant_id: @variant.id,
          delta_on_hand: 9,
          reason: "stock.received",
          idempotency_key: "strict-idempotency-#{unique}",
          metadata: { "source" => "test" }
        )
      end.to raise_error(Inventory::Adjuster::IdempotencyConflictError)

      expect(InventoryLevel.find_by!(product_variant_id: @variant.id, inventory_location_id: @location.id).on_hand).to eq(4)
      expect(InventoryLedgerEntry.where(idempotency_key: "strict-idempotency-#{unique}").count).to eq(1)
    end
  end

  it "rejects forged cross-store inventory scopes inside the same tenant" do
    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      expect do
        Inventory::Adjuster.call(
          store_id: @other_store.id,
          inventory_location_id: @other_location.id,
          product_variant_id: @variant.id,
          delta_on_hand: 1,
          reason: "forged.cross-store",
          idempotency_key: "forged-cross-store-#{unique}"
        )
      end.to raise_error(ActiveRecord::RecordNotFound)

      expect(InventoryLedgerEntry.where(idempotency_key: "forged-cross-store-#{unique}")).to be_empty
    end
  end
end
