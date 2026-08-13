require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Merchant tenant directory", type: :request do
  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @user_one_id = SecureRandom.uuid
    @user_two_id = SecureRandom.uuid
    @tenant_one_id = SecureRandom.uuid
    @tenant_two_id = SecureRandom.uuid
    @store_one_id = SecureRandom.uuid
    @store_two_id = SecureRandom.uuid

    create_identity(
      user_id: @user_one_id,
      email: "tenant-directory-one-#{SecureRandom.hex(6)}@example.test",
      tenant_id: @tenant_one_id,
      tenant_name: "Tenant Directory One",
      tenant_slug: "tenant-directory-one-#{SecureRandom.hex(4)}",
      store_id: @store_one_id,
      store_name: "Store One",
      store_slug: "store-one-#{SecureRandom.hex(4)}"
    )

    create_identity(
      user_id: @user_two_id,
      email: "tenant-directory-two-#{SecureRandom.hex(6)}@example.test",
      tenant_id: @tenant_two_id,
      tenant_name: "Tenant Directory Two",
      tenant_slug: "tenant-directory-two-#{SecureRandom.hex(4)}",
      store_id: @store_two_id,
      store_name: "Store Two",
      store_slug: "store-two-#{SecureRandom.hex(4)}"
    )

    @token = Auth::SessionIssuer.call(user_id: @user_one_id, ip_address: "127.0.0.1").token
  end

  after do
    cleanup
    @admin&.close
    Current.reset
  end

  it "returns only tenants belonging to the authenticated user without a tenant context header" do
    get "/v1/tenants", headers: { "Authorization" => "Bearer #{@token}" }

    expect(response).to have_http_status(:ok)
    tenants = response.parsed_body.fetch("tenants")

    expect(tenants.length).to eq(1)
    expect(tenants.first.fetch("id")).to eq(@tenant_one_id)
    expect(tenants.first.fetch("name")).to eq("Tenant Directory One")
    expect(tenants.first.fetch("stores_count")).to eq(1)
    expect(tenants.first.dig("membership", "role")).to eq("owner")
    expect(tenants.first.fetch("accessible")).to be(true)
    expect(tenants.map { |tenant| tenant.fetch("id") }).not_to include(@tenant_two_id)
  end

  it "requires an authenticated merchant session" do
    get "/v1/tenants"

    expect(response).to have_http_status(:unauthorized)
  end

  private

  def create_identity(user_id:, email:, tenant_id:, tenant_name:, tenant_slug:, store_id:, store_name:, store_slug:)
    @admin.exec_params(
      "INSERT INTO users (id, email, status, mfa_enabled, created_at, updated_at) VALUES ($1, $2, 'active', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
      [user_id, email]
    )
    @admin.exec_params(
      "INSERT INTO tenants (id, name, slug, status, created_at, updated_at) VALUES ($1, $2, $3, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
      [tenant_id, tenant_name, tenant_slug]
    )
    @admin.exec_params(
      "INSERT INTO memberships (id, tenant_id, user_id, role, status, created_at, updated_at) VALUES ($1, $2, $3, 'owner', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
      [SecureRandom.uuid, tenant_id, user_id]
    )
    @admin.exec_params(
      "INSERT INTO stores (id, tenant_id, name, slug, status, created_at, updated_at) VALUES ($1, $2, $3, $4, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
      [store_id, tenant_id, store_name, store_slug]
    )
  end

  def cleanup
    return unless @admin

    user_ids = [@user_one_id, @user_two_id].compact
    tenant_ids = [@tenant_one_id, @tenant_two_id].compact
    return if user_ids.empty? || tenant_ids.empty?

    user_list = user_ids.map { |id| @admin.escape_literal(id) }.join(",")
    tenant_list = tenant_ids.map { |id| @admin.escape_literal(id) }.join(",")

    @admin.exec("DELETE FROM security_events WHERE actor_user_id IN (#{user_list})")
    @admin.exec("DELETE FROM sessions WHERE user_id IN (#{user_list})")
    @admin.exec("DELETE FROM stores WHERE tenant_id IN (#{tenant_list})")
    @admin.exec("DELETE FROM memberships WHERE tenant_id IN (#{tenant_list})")
    @admin.exec("DELETE FROM tenants WHERE id IN (#{tenant_list})")
    @admin.exec("DELETE FROM users WHERE id IN (#{user_list})")
  rescue PG::UndefinedTable
    nil
  end
end
