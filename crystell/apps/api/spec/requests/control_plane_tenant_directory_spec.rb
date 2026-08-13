require "rails_helper"
require "pg"
require "rotp"
require "securerandom"

RSpec.describe "Control plane tenant directory API", type: :request do
  let(:control_password) { "Crystell-Control-Tenant-API-2026!" }
  let(:merchant_password) { "Crystell-Merchant-Tenant-API-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    cleanup_control_plane

    @control = ControlPlane::BootstrapOwner.call(
      email: "tenant-api-control-#{unique}@example.test",
      password: control_password
    )

    post "/control/v1/session", params: {
      email: @control.user.email,
      password: control_password,
      otp: ROTP::TOTP.new(@control.mfa_secret).now
    }, as: :json
    expect(response).to have_http_status(:created)
    @control_token = response.parsed_body.fetch("token")

    post "/v1/auth/registration", params: {
      email: "tenant-api-merchant-#{unique}@example.test",
      password: merchant_password,
      tenant_name: "Tenant API #{unique}",
      tenant_slug: "tenant-api-#{unique}",
      store_name: "Tenant API Store #{unique}",
      store_slug: "tenant-api-store-#{unique}"
    }, as: :json
    expect(response).to have_http_status(:created)
    @merchant_token = response.parsed_body.fetch("token")
  end

  after do
    cleanup_control_plane
    @admin&.close
    ControlPlaneCurrent.reset
    Current.reset
  end

  it "returns only safe directory fields to an authenticated control-plane user" do
    get "/control/v1/tenants",
        params: { q: "tenant-api-#{unique}" },
        headers: { "Authorization" => "Bearer #{@control_token}" }

    expect(response).to have_http_status(:ok)
    tenant = response.parsed_body.fetch("tenants").first
    expect(tenant.fetch("slug")).to eq("tenant-api-#{unique}")
    expect(tenant.keys).to match_array(%w[id name slug status stores_count active_stores_count created_at])
    expect(ControlPlaneAuditEvent.where(action: "control_plane.tenant_directory_viewed").count).to eq(1)
  end

  it "rejects merchant and unauthenticated tokens" do
    get "/control/v1/tenants", headers: { "Authorization" => "Bearer #{@merchant_token}" }
    expect(response).to have_http_status(:unauthorized)

    get "/control/v1/tenants"
    expect(response).to have_http_status(:unauthorized)
  end

  private

  def cleanup_control_plane
    return unless @admin

    @admin.exec("DELETE FROM control_plane_audit_events")
    @admin.exec("DELETE FROM control_plane_sessions")
    @admin.exec("DELETE FROM control_plane_users")
  rescue PG::UndefinedTable
    nil
  end
end
