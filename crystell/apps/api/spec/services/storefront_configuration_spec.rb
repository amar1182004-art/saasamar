require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Storefront configuration" do
  let(:password) { "Crystell-Storefront-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @tenant_a = Auth::AccountRegistration.call(
      email: "storefront-owner-a-#{unique}@example.test",
      password: password,
      tenant_name: "Storefront Tenant A #{unique}",
      tenant_slug: "storefront-tenant-a-#{unique}",
      store_name: "Storefront Store A #{unique}",
      store_slug: "storefront-store-a-#{unique}"
    )
    @tenant_b = Auth::AccountRegistration.call(
      email: "storefront-owner-b-#{unique}@example.test",
      password: password,
      tenant_name: "Storefront Tenant B #{unique}",
      tenant_slug: "storefront-tenant-b-#{unique}",
      store_name: "Storefront Store B #{unique}",
      store_slug: "storefront-store-b-#{unique}"
    )
    @owner_a = IdentityScope.with(@tenant_a.user_id) { User.find(@tenant_a.user_id) }
    @owner_b = IdentityScope.with(@tenant_b.user_id) { User.find(@tenant_b.user_id) }

    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      @store_a = Store.find_by!(slug: "storefront-store-a-#{unique}")
    end
    TenantAccess.with(user: @owner_b, tenant_id: @tenant_b.tenant_id) do
      @store_b = Store.find_by!(slug: "storefront-store-b-#{unique}")
    end
  end

  after do
    tenant_ids = [@tenant_a&.tenant_id, @tenant_b&.tenant_id].compact
    unless tenant_ids.empty? || @admin.nil?
      placeholders = tenant_ids.each_index.map { |index| "$#{index + 1}::uuid" }.join(", ")
      @admin.exec_params("DELETE FROM storefront_configurations WHERE tenant_id IN (#{placeholders})", tenant_ids)
    end
    @admin&.close
    Current.reset
  end

  it "keeps draft changes away from the published snapshot until publish" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      initial = Storefront::ConfigurationManager.read(store_id: @store_a.id)
      expect(initial.id).to be_nil
      expect(initial.status).to eq("offline")
      expect(initial.draft_version).to eq(0)

      updated = Storefront::ConfigurationManager.update(
        store_id: @store_a.id,
        status: "online",
        config: {
          theme_key: "crystell-modern",
          locale: "ar-EG",
          currency_code: "egp",
          settings: { announcement_bar: { enabled: true } }
        }
      )

      expect(updated.status).to eq("online")
      expect(updated.draft_config.fetch("currency_code")).to eq("EGP")
      expect(updated.draft_version).to eq(1)
      expect(updated.published_version).to eq(0)
      expect(updated.published_config.fetch("theme_key")).to eq("default")

      published = Storefront::ConfigurationManager.publish(store_id: @store_a.id)
      expect(published.published_version).to eq(1)
      expect(published.published_config).to eq(published.draft_config)
      expect(published.published_at).to be_present
    end
  end

  it "deep-merges settings and rejects unknown or oversized configuration" do
    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      Storefront::ConfigurationManager.update(
        store_id: @store_a.id,
        config: { settings: { header: { sticky: true }, footer: { compact: false } } }
      )
      updated = Storefront::ConfigurationManager.update(
        store_id: @store_a.id,
        config: { settings: { header: { transparent: true } } }
      )

      expect(updated.draft_config.dig("settings", "header")).to eq({ "sticky" => true, "transparent" => true })
      expect(updated.draft_config.dig("settings", "footer", "compact")).to be(false)

      expect do
        Storefront::ConfigurationManager.update(store_id: @store_a.id, config: { custom_javascript: "alert(1)" })
      end.to raise_error(Storefront::ConfigurationManager::InvalidConfigurationError)

      expect do
        Storefront::ConfigurationManager.update(
          store_id: @store_a.id,
          config: { settings: { payload: "x" * 70_000 } }
        )
      end.to raise_error(Storefront::ConfigurationManager::InvalidConfigurationError, /too large/)
    end
  end

  it "hides another tenant store and configuration through RLS" do
    foreign_config_id = nil
    TenantAccess.with(user: @owner_b, tenant_id: @tenant_b.tenant_id) do
      foreign = Storefront::ConfigurationManager.update(
        store_id: @store_b.id,
        config: { theme_key: "foreign-theme" }
      )
      foreign_config_id = foreign.id
    end

    TenantAccess.with(user: @owner_a, tenant_id: @tenant_a.tenant_id) do
      expect(Store.find_by(id: @store_b.id)).to be_nil
      expect(StorefrontConfiguration.find_by(id: foreign_config_id)).to be_nil
      expect do
        Storefront::ConfigurationManager.read(store_id: @store_b.id)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "rejects a cross-tenant store/config relationship at PostgreSQL" do
    expect do
      @admin.exec_params(
        <<~SQL,
          INSERT INTO storefront_configurations (id, tenant_id, store_id, status, draft_config, published_config, draft_version, published_version, lock_version, created_at, updated_at)
          VALUES (gen_random_uuid(), $1::uuid, $2::uuid, 'offline', '{}'::jsonb, '{}'::jsonb, 0, 0, 0, NOW(), NOW())
        SQL
        [@tenant_a.tenant_id, @store_b.id]
      )
    end.to raise_error(PG::ForeignKeyViolation)
  end
end
