require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Checkout inventory allocation" do
  let(:password) { "Crystell-Checkout-Inventory-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @registration = Auth::AccountRegistration.call(
      email: "checkout-inventory-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Checkout Inventory Tenant #{unique}",
      tenant_slug: "checkout-inventory-tenant-#{unique}",
      store_name: "Checkout Inventory Store #{unique}",
      store_slug: "checkout-inventory-store-#{unique}"
    )
    @owner = IdentityScope.with(@registration.user_id) { User.find(@registration.user_id) }

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      @store = Store.find_by!(slug: "checkout-inventory-store-#{unique}")
      @store.update!(status: "active")
      product = Catalog::ProductCreator.call(
        store_id: @store.id,
        attributes: {
          title: "Inventory Checkout Product #{unique}",
          slug: "inventory-checkout-product-#{unique}",
          status: "active",
          published_at: Time.current
        },
        variants: [{
          title: "Default",
          sku: "CHECKOUT-INV-#{unique}",
          currency: "EGP",
          price_cents: 25_000,
          track_inventory: true
        }]
      )
      @variant = product.product_variants.first!
      @primary = InventoryLocation.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        name: "Primary Warehouse #{unique}",
        code: "primary-#{unique}",
        priority: 0
      )
      @backup = InventoryLocation.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        name: "Backup Warehouse #{unique}",
        code: "backup-#{unique}",
        priority: 10
      )
      seed_stock!(@primary, 2, "primary")
      seed_stock!(@backup, 3, "backup")
    end
  end

  after do
    tenant_id = @registration&.tenant_id
    if tenant_id.present? && @admin
      %w[
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

  it "allocates tracked inventory across active locations in priority order" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      checkout = build_checkout!(quantity: 4, key: "priority")
      result = Checkout::InventoryAllocator.call(checkout_session_id: checkout.id)
      mappings = CheckoutInventoryReservation.where(checkout_session_id: checkout.id).to_a

      expect(result.status).to eq("inventory_reserved")
      expect(result.reserved_quantity).to eq(4)
      expect(mappings.sum(&:quantity)).to eq(4)

      primary_mapping = mappings.find { |mapping| mapping.inventory_location_id == @primary.id }
      backup_mapping = mappings.find { |mapping| mapping.inventory_location_id == @backup.id }
      expect(primary_mapping.quantity).to eq(2)
      expect(backup_mapping.quantity).to eq(2)

      primary_level = InventoryLevel.find_by!(inventory_location_id: @primary.id, product_variant_id: @variant.id)
      backup_level = InventoryLevel.find_by!(inventory_location_id: @backup.id, product_variant_id: @variant.id)
      expect(primary_level.reserved).to eq(2)
      expect(backup_level.reserved).to eq(2)
    end
  end

  it "is idempotent once the checkout inventory has been reserved" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      checkout = build_checkout!(quantity: 4, key: "idempotent")
      first = Checkout::InventoryAllocator.call(checkout_session_id: checkout.id)
      second = Checkout::InventoryAllocator.call(checkout_session_id: checkout.id)

      expect(second.reservation_ids).to eq(first.reservation_ids)
      expect(CheckoutInventoryReservation.where(checkout_session_id: checkout.id).count).to eq(2)
      expect(InventoryReservation.where(id: first.reservation_ids).count).to eq(2)
    end
  end

  it "rolls back every partial reservation when total stock is insufficient" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      checkout = build_checkout!(quantity: 6, key: "insufficient")

      expect do
        Checkout::InventoryAllocator.call(checkout_session_id: checkout.id)
      end.to raise_error(Checkout::InventoryAllocator::InsufficientStockError)

      expect(checkout.reload.status).to eq("open")
      expect(CheckoutInventoryReservation.where(checkout_session_id: checkout.id)).to be_empty
      expect(InventoryReservation.where(reference_type: "CheckoutLineItem", reference_id: checkout.checkout_line_items.first.id)).to be_empty

      primary_level = InventoryLevel.find_by!(inventory_location_id: @primary.id, product_variant_id: @variant.id)
      backup_level = InventoryLevel.find_by!(inventory_location_id: @backup.id, product_variant_id: @variant.id)
      expect(primary_level.reserved).to eq(0)
      expect(backup_level.reserved).to eq(0)
    end
  end

  it "does not reserve stock for variants that do not track inventory" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      @variant.update!(track_inventory: false)
      checkout = build_checkout!(quantity: 20, key: "untracked")
      result = Checkout::InventoryAllocator.call(checkout_session_id: checkout.id)

      expect(result.status).to eq("inventory_reserved")
      expect(result.reserved_quantity).to eq(0)
      expect(CheckoutInventoryReservation.where(checkout_session_id: checkout.id)).to be_empty
    end
  end

  it "keeps direct inventory balance updates forbidden to the runtime role" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      level = InventoryLevel.find_by!(inventory_location_id: @primary.id, product_variant_id: @variant.id)
      connection = ApplicationRecord.connection

      expect do
        ApplicationRecord.transaction(requires_new: true) do
          connection.execute("SAVEPOINT runtime_inventory_direct_write")
          begin
            connection.execute("UPDATE inventory_levels SET reserved = reserved + 1 WHERE id = #{connection.quote(level.id)}::uuid")
          ensure
            connection.execute("ROLLBACK TO SAVEPOINT runtime_inventory_direct_write")
          end
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end
  end

  private

  def seed_stock!(location, quantity, suffix)
    Inventory::Adjuster.call(
      store_id: @store.id,
      inventory_location_id: location.id,
      product_variant_id: @variant.id,
      delta_on_hand: quantity,
      reason: "stock.received",
      idempotency_key: "checkout-inventory-seed-#{suffix}-#{unique}"
    )
  end

  def build_checkout!(quantity:, key:)
    created = Commerce::CartManager.create(store_id: @store.id)
    Commerce::CartManager.add_item(
      store_id: @store.id,
      access_token: created.access_token,
      product_variant_id: @variant.id,
      quantity: quantity
    )
    Checkout::SessionCreator.call(
      store_id: @store.id,
      cart_access_token: created.access_token,
      idempotency_key: "checkout-inventory-#{key}-#{unique}"
    )
  end
end
