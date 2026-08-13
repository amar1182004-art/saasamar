require "rails_helper"
require "digest"
require "pg"
require "rotp"
require "securerandom"

RSpec.describe "Control plane audit and security APIs", type: :request do
  let(:password) { "Crystell-Control-Audit-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    cleanup_control_plane

    @owner = ControlPlane::BootstrapOwner.call(
      email: "audit-owner-#{unique}@example.test",
      password: password
    )

    post "/control/v1/session", params: {
      email: @owner.user.email,
      password: password,
      otp: ROTP::TOTP.new(@owner.mfa_secret).now
    }, as: :json
    expect(response).to have_http_status(:created)
    @owner_token = response.parsed_body.fetch("token")
  end

  after do
    cleanup_control_plane
    @admin&.close
    ControlPlaneCurrent.reset
  end

  it "returns a paginated audit stream with sensitive metadata redacted" do
    event = ControlPlaneAuditEvent.create!(
      control_plane_user_id: @owner.user.id,
      action: "control_plane.test_sensitive_metadata",
      target_type: "TestTarget",
      target_id: SecureRandom.uuid,
      metadata: {
        "safe" => "visible",
        "api_token" => "must-not-leak",
        "nested" => {
          "password" => "must-not-leak-either",
          "label" => "still-visible"
        }
      },
      occurred_at: Time.current
    )

    get "/control/v1/audit-events",
        params: { action: event.action, limit: 10 },
        headers: bearer(@owner_token)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("pagination").fetch("has_more")).to be(false)

    returned = payload.fetch("audit_events").first
    expect(returned.fetch("id")).to eq(event.id)
    expect(returned.dig("metadata", "safe")).to eq("visible")
    expect(returned.dig("metadata", "api_token")).to eq("[REDACTED]")
    expect(returned.dig("metadata", "nested", "password")).to eq("[REDACTED]")
    expect(returned.dig("metadata", "nested", "label")).to eq("still-visible")
    expect(ControlPlaneAuditEvent.where(action: "control_plane.audit_log_viewed").count).to eq(1)
  end

  it "allows audit viewers but reserves the security center for security.read" do
    viewer_token = create_viewer_session

    get "/control/v1/audit-events", headers: bearer(viewer_token)
    expect(response).to have_http_status(:ok)

    get "/control/v1/security", headers: bearer(viewer_token)
    expect(response).to have_http_status(:forbidden)

    get "/control/v1/security", headers: bearer(@owner_token)
    expect(response).to have_http_status(:ok)

    security = response.parsed_body.fetch("security")
    expect(security.dig("users", "total")).to be >= 2
    expect(security.dig("sessions", "active")).to be >= 2
    expect(security.dig("activity_24h", "audit_events")).to be >= 1
    expect(ControlPlaneAuditEvent.where(action: "control_plane.security_overview_viewed").count).to eq(1)
  end

  private

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_viewer_session
    secret = ROTP::Base32.random_base32
    viewer = ControlPlaneUser.create!(
      email: "audit-viewer-#{unique}@example.test",
      password: password,
      role: "viewer",
      status: "active",
      mfa_secret: secret,
      mfa_enabled_at: Time.current
    )

    token = SecureRandom.urlsafe_base64(48)
    ControlPlaneSession.create!(
      control_plane_user_id: viewer.id,
      token_digest: Digest::SHA256.hexdigest(token),
      expires_at: 30.minutes.from_now,
      mfa_verified_at: Time.current,
      last_seen_at: Time.current
    )
    token
  end

  def cleanup_control_plane
    return unless @admin

    @admin.exec("DELETE FROM control_plane_audit_events")
    @admin.exec("DELETE FROM control_plane_sessions")
    @admin.exec("DELETE FROM control_plane_users")
  rescue PG::UndefinedTable
    nil
  end
end
