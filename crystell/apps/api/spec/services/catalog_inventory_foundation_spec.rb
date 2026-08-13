require "rails_helper"
require "pg"
require "securerandom"
require "thread"

RSpec.describe "Catalog and inventory foundation" do
  let(:password) { "Crystell-Catalog-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))

    @tenant_a = Auth::AccountRegistration.call(
      email: "catalog-owner-a-#{unique}@example.test",
      password: password,
      tenant_name: "Catalog Tenant A #{unique}",
      tenant_slug: "catalog-tenant-a-#{unique}",
      store_name: "Catalog Store A #{unique}",
      store_slug: "catalog-store-a-#{unique}"
    )
    @tenant_b = Auth::AccountRegistration.call(
      email: "catalog-owner-b-#{unique}@example.test",
      password: password,
      tenant_name: "Catalog Tenant B #{unique}",
      tenant_slug: "catalog-tenant-b-#{unique}",
      store_name: "Catalog Store B #{unique}",
      store_slug: "catalog-store-b-#{unique}"
    )

    @owner_a = IdentityScope.with(@tenant_a.user_id) { User.find(@tenant_a.user_id) }
    @owner_b = IdentityScope.with(@tenant_b.user_id) { User.find(@tenant_b.user_id) }

    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      @store_a = Store.find_by!(slug: "catalog-store-a-#{unique}")
      @store_a2 = Store.create!(
        tenant_id: Current.tenant_id,
        name: "Catalog Store A2 #{unique}",
        slug: "catalog-store-a2-#{unique}"
      )
    end

    TenantAccess.with(user: @owner_b, tenant_id: @tenant_b.tenant_id) do
      @store_b = Store.find_by!(slug: "catalog-store-b-#{unique}")
    end
  end

  after do
    tenant_ids = [@tenant_a&.tenant_id, @tenant_b&.tenant_id].compact
    unless tenant_ids.empty? || @admin.nil?
      placeholders = tenant_ids.each_index.map { |index| "$#{index + 1}::uuid" }.join(", ")
      %w[
        inventory_ledger_entries
        inventory_reservations
        inventory_levels
        inventory_locations
        product_category_assignments
        categories
        product_variants
        products
      ].each do |table|
        @admin.exec_params("DELETE FROM #{table} WHERE tenant_id IN (#{placeholders})", tenant_ids)
      end
    end

    @admin&.close
    Current.reset
  end

  it "creates a product and variants atomically and hides them from another tenant" do
    product_id = nil

    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      product = Catalog::ProductCreator.call(
        store_id: @store_a.id,
        attributes: {
          title: "Premium Chair",
          slug: "premium-chair",
          status: "active",
          published_at: Time.current
        },
        variants: [
          { title: "Black", sku: "CHAIR-BLK-#{unique}", currency: "EGP", price_cents: 150_000 },
          { title: "White", sku: "CHAIR-WHT-#{unique}", currency: "EGP", price_cents: 155_000 }
        ]
      )

      product_id = product.id
      expect(product.product_variants.count).to eq(2)
      expect(product.tenant_id).to eq(@tenant_a.tenant_id)
      expect(product.store_id).to eq(@store_a.id)
    end

    TenantAccess.with(user: @owner_b, tenant_id: @tenant_b.tenant_id) do
      expect(Product.find_by(id: product_id)).to be_nil
    end
  end

  it "rejects cross-store variant forgery at PostgreSQL even inside one tenant" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      product = Catalog::ProductCreator.call(
        store_id: @store_a.id,
        attributes: { title: "Scoped Product", slug: "scoped-product" },
        variants: [{ title: "Default", currency: "EGP", price_cents: 10_000 }]
      )

      expect do
        ProductVariant.create!(
          tenant_id: Current.tenant_id,
          store_id: @store_a2.id,
          product_id: product.id,
          title: "Forged",
          currency: "EGP",
          price_cents: 10_000
        )
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  it "meters stock adjustments idempotently through the append-only ledger" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      variant = create_variant!
      location = create_location!

      first = Inventory::Adjuster.call(
        store_id: @store_a.id,
        inventory_location_id: location.id,
        product_variant_id: variant.id,
        delta_on_hand: 10,
        reason: "stock.received",
        idempotency_key: "adjust-#{unique}"
      )
      duplicate = Inventory::Adjuster.call(
        store_id: @store_a.id,
        inventory_location_id: location.id,
        product_variant_id: variant.id,
        delta_on_hand: 10,
        reason: "stock.received",
        idempotency_key: "adjust-#{unique}"
      )

      expect(first.recorded).to be(true)
      expect(first.on_hand).to eq(10)
      expect(duplicate.recorded).to be(false)
      expect(duplicate.on_hand).to eq(10)
      expect(InventoryLedgerEntry.where(product_variant_id: variant.id).count).to eq(1)
    end
  end

  it "reserves and consumes stock without double-counting duplicate requests" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      variant = create_variant!
      location = create_location!
      Inventory::Adjuster.call(
        store_id: @store_a.id,
        inventory_location_id: location.id,
        product_variant_id: variant.id,
        delta_on_hand: 10,
        reason: "stock.received",
        idempotency_key: "seed-#{unique}"
      )

      reserved = Inventory::ReservationManager.reserve(
        store_id: @store_a.id,
        inventory_location_id: location.id,
        product_variant_id: variant.id,
        quantity: 4,
        idempotency_key: "reserve-#{unique}"
      )
      duplicate = Inventory::ReservationManager.reserve(
        store_id: @store_a.id,
        inventory_location_id: location.id,
        product_variant_id: variant.id,
        quantity: 4,
        idempotency_key: "reserve-#{unique}"
      )

      expect(reserved.recorded).to be(true)
      expect(reserved.reserved).to eq(4)
      expect(reserved.available).to eq(6)
      expect(duplicate.recorded).to be(false)
      expect(duplicate.reserved).to eq(4)

      consumed = Inventory::ReservationManager.consume(reservation_id: reserved.reservation_id)
      expect(consumed.recorded).to be(true)
      expect(consumed.status).to eq("consumed")
      expect(consumed.on_hand).to eq(6)
      expect(consumed.reserved).to eq(0)
      expect(consumed.available).to eq(6)
    end
  end

  it "serializes competing reservations so the last unit cannot be oversold" do
    variant_id = nil
    location_id = nil

    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      variant = create_variant!
      location = create_location!
      variant_id = variant.id
      location_id = location.id

      Inventory::Adjuster.call(
        store_id: @store_a.id,
        inventory_location_id: location.id,
        product_variant_id: variant.id,
        delta_on_hand: 1,
        reason: "stock.received",
        idempotency_key: "seed-concurrent-#{unique}"
      )
    end

    start_gate = Queue.new
    results = Queue.new

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
            start_gate.pop
            begin
              reservation = Inventory::ReservationManager.reserve(
                store_id: @store_a.id,
                inventory_location_id: location_id,
                product_variant_id: variant_id,
                quantity: 1,
                idempotency_key: "concurrent-reserve-#{unique}-#{index}"
              )
              results << [:reserved, reservation.reservation_id]
            rescue Inventory::ReservationManager::InsufficientStockError
              results << [:insufficient, nil]
            end
          end
        end
      end
    end

    2.times { start_gate << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop.first }

    expect(outcomes.count(:reserved)).to eq(1)
    expect(outcomes.count(:insufficient)).to eq(1)

    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      level = InventoryLevel.find_by!(
        inventory_location_id: location_id,
        product_variant_id: variant_id
      )
      expect(level.on_hand).to eq(1)
      expect(level.reserved).to eq(1)
      expect(level.available).to eq(0)
      expect(InventoryReservation.active.where(product_variant_id: variant_id).count).to eq(1)
    end
  end

  it "rejects reservations above available inventory without changing stock" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      variant = create_variant!
      location = create_location!
      Inventory::Adjuster.call(
        store_id: @store_a.id,
        inventory_location_id: location.id,
        product_variant_id: variant.id,
        delta_on_hand: 2,
        reason: "stock.received",
        idempotency_key: "seed-low-#{unique}"
      )

      expect do
        Inventory::ReservationManager.reserve(
          store_id: @store_a.id,
          inventory_location_id: location.id,
          product_variant_id: variant.id,
          quantity: 3,
          idempotency_key: "reserve-too-much-#{unique}"
        )
      end.to raise_error(Inventory::ReservationManager::InsufficientStockError)

      level = InventoryLevel.find_by!(product_variant_id: variant.id, inventory_location_id: location.id)
      expect(level.on_hand).to eq(2)
      expect(level.reserved).to eq(0)
    end
  end

  it "blocks cross-tenant catalog writes at PostgreSQL" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      connection = ApplicationRecord.connection

      expect do
        connection.execute(<<~SQL)
          INSERT INTO products (
            id, tenant_id, store_id, title, slug, status, metadata, lock_version, created_at, updated_at
          ) VALUES (
            gen_random_uuid(),
            #{connection.quote(@tenant_b.tenant_id)},
            #{connection.quote(@store_b.id)},
            'Forbidden',
            'forbidden-#{unique}',
            'draft',
            '{}'::jsonb,
            0,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
          )
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /row-level security|policy/i)
    end
  end

  def create_variant!
    product = Catalog::ProductCreator.call(
      store_id: @store_a.id,
      attributes: { title: "Inventory Product #{unique}", slug: "inventory-product-#{SecureRandom.hex(4)}" },
      variants: [{ title: "Default", sku: "INV-#{SecureRandom.hex(4)}", currency: "EGP", price_cents: 20_000 }]
    )
    product.product_variants.first!
  end

  def create_location!
    InventoryLocation.create!(
      tenant_id: Current.tenant_id,
      store_id: @store_a.id,
      name: "Main Warehouse #{SecureRandom.hex(4)}",
      code: "main-#{SecureRandom.hex(4)}"
    )
  end
end
