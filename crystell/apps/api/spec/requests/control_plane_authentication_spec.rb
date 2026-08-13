require "rails_helper"
require "pg"
require "rotp"
require "securerandom"

RSpec.describe "Control plane authentication boundary", type: :request do
  let(:control_password) { "Crystell-Control-HTTP-2026!" }
  let(:merchant_password) { "Crystell-Merchant-HTTP-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    cleanup_control_plane
    @control = ControlPlane::BootstrapOwner.call(
      email: "control-http-#{unique}@example.test",
      password: control_password
    )
  end

  after do
    cleanup_control_plane
    @admin&.close
    ControlPlaneCurrent.reset
    Current.reset
  end

  it "issues only MFA-verified control sessions and keeps merchant/control tokens non-interchangeable" do
    post "/control/v1/session", params: {
      email: @control.user.email,
      password: control_password,
      otp: ROTP::TOTP.new(@control.mfa_secret).now
    }, as: :json

    expect(response).to have_http_status(:created)
    control_token = response.parsed_body.fetch("token")

    get "/control/v1/me", headers: { "Authorization" => "Bearer #{control_token}" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("user", "role")).to eq("owner")

    get "/v1/me", headers: { "Authorization" => "Bearer #{control_token}" }
    expect(response).to have_http_status(:unauthorized)

    post "/v1/auth/registration", params: {
      email: "merchant-http-#{unique}@example.test",
      password: merchant_password,
      tenant_name: "Merchant HTTP #{unique}",
      tenant_slug: "merchant-http-#{unique}",
      store_name: "Merchant Store #{unique}",
      store_slug: "merchant-store-#{unique}"
    }, as: :json

    expect(response).to have_http_status(:created)
    merchant_token = response.parsed_body.fetch("token")

    get "/control/v1/me", headers: { "Authorization" => "Bearer #{merchant_token}" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "never creates a control session without a valid MFA code" do
    post "/control/v1/session", params: {
      email: @control.user.email,
      password: control_password,
      otp: "000000"
    }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(ControlPlaneSession.count).to eq(0)
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
