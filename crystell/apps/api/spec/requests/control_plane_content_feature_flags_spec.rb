require "rails_helper"
require "digest"
require "pg"
require "rotp"
require "securerandom"

RSpec.describe "Control plane content and feature flag APIs", type: :request do
  let(:password) { "Crystell-Control-CMS-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    cleanup_control_plane

    @owner = ControlPlane::BootstrapOwner.call(
      email: "cms-owner-#{unique}@example.test",
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

  it "lets viewers read content while keeping draft writes admin-only" do
    put "/control/v1/content/platform-branding",
        params: {
          content_document: {
            kind: "branding",
            locale: "en",
            content: { name: "Crystell", accent: "red" },
            reason: "Initial platform branding"
          }
        },
        headers: bearer(@owner_token),
        as: :json
    expect(response).to have_http_status(:ok)

    viewer_token = create_viewer_session

    get "/control/v1/content/platform-branding", headers: bearer(viewer_token)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("content_document", "draft_content", "name")).to eq("Crystell")

    put "/control/v1/content/platform-branding",
        params: {
          content_document: {
            kind: "branding",
            content: { name: "Blocked" }
          }
        },
        headers: bearer(viewer_token),
        as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "requires elevation for publish and performs rollback as a new immutable version" do
    put_content(title: "Version One")

    post "/control/v1/content/home-page/publish",
         params: { publication: { reason: "Publish approved homepage" } },
         headers: bearer(@owner_token),
         as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("error")).to eq("privilege_elevation_required")

    elevate_owner_session

    post "/control/v1/content/home-page/publish",
         params: { publication: { reason: "Publish approved homepage" } },
         headers: bearer(@owner_token),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("content_document", "published_version")).to eq(1)

    put_content(title: "Version Two")

    post "/control/v1/content/home-page/publish",
         params: { publication: { reason: "Publish second homepage" } },
         headers: bearer(@owner_token),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("content_document", "published_version")).to eq(2)

    post "/control/v1/content/home-page/rollback",
         params: { rollback: { version: 1, reason: "Restore approved homepage" } },
         headers: bearer(@owner_token),
         as: :json
    expect(response).to have_http_status(:ok)
    rolled_back = response.parsed_body.fetch("content_document")
    expect(rolled_back.fetch("draft_version")).to eq(3)
    expect(rolled_back.fetch("published_version")).to eq(3)
    expect(rolled_back.dig("published_content", "title")).to eq("Version One")

    get "/control/v1/content/home-page/versions", headers: bearer(@owner_token)
    expect(response).to have_http_status(:ok)
    versions = response.parsed_body.fetch("content_versions")
    expect(versions.map { |entry| entry.fetch("version") }).to eq([3, 2, 1])
    expect(versions.first.fetch("source")).to eq("rollback")

    expect(ControlPlaneAuditEvent.where(action: "control_plane.content_published").count).to eq(2)
    expect(ControlPlaneAuditEvent.where(action: "control_plane.content_rolled_back").count).to eq(1)
  end

  it "protects live feature flags with elevation and rejects secret-like configuration" do
    viewer_token = create_viewer_session

    get "/control/v1/feature-flags", headers: bearer(viewer_token)
    expect(response).to have_http_status(:ok)

    put "/control/v1/feature-flags/new-checkout",
        params: {
          feature_flag: {
            enabled: true,
            rollout_percentage: 10,
            reason: "Enable checkout pilot"
          }
        },
        headers: bearer(viewer_token),
        as: :json
    expect(response).to have_http_status(:forbidden)

    put "/control/v1/feature-flags/new-checkout",
        params: {
          feature_flag: {
            enabled: true,
            rollout_percentage: 10,
            reason: "Enable checkout pilot"
          }
        },
        headers: bearer(@owner_token),
        as: :json
    expect(response).to have_http_status(:conflict)

    elevate_owner_session

    put "/control/v1/feature-flags/new-checkout",
        params: {
          feature_flag: {
            description: "Controlled checkout rollout",
            enabled: true,
            rollout_percentage: 10,
            config: { cohort: "pilot" },
            reason: "Enable checkout pilot"
          }
        },
        headers: bearer(@owner_token),
        as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("feature_flag", "enabled")).to be(true)
    expect(response.parsed_body.dig("feature_flag", "rollout_percentage")).to eq(10)

    put "/control/v1/feature-flags/new-checkout",
        params: {
          feature_flag: {
            config: { api_token: "must-never-be-stored" },
            reason: "Attempt unsafe configuration"
          }
        },
        headers: bearer(@owner_token),
        as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("details")).to include("secret-like key")
    expect(ControlPlaneFeatureFlag.find_by!(key: "new-checkout").config).to eq({ "cohort" => "pilot" })
    expect(ControlPlaneAuditEvent.where(action: "control_plane.feature_flag_updated").count).to eq(1)
  end

  it "rejects secret-like CMS payloads before storing a draft" do
    put "/control/v1/content/platform-branding",
        params: {
          content_document: {
            kind: "branding",
            content: { logo_url: "https://example.test/logo.svg", api_key: "must-not-store" },
            reason: "Unsafe draft"
          }
        },
        headers: bearer(@owner_token),
        as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("details")).to include("secret-like key")
    expect(ControlPlaneContentDocument.where(key: "platform-branding")).to be_empty
  end

  private

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def put_content(title:)
    put "/control/v1/content/home-page",
        params: {
          content_document: {
            kind: "page",
            locale: "en",
            content: { title: title, sections: [{ type: "hero", heading: title }] },
            reason: "Update homepage draft"
          }
        },
        headers: bearer(@owner_token),
        as: :json
    expect(response).to have_http_status(:ok)
  end

  def elevate_owner_session
    digest = Digest::SHA256.hexdigest(@owner_token)
    ControlPlaneSession.find_by!(token_digest: digest).update!(privilege_elevated_until: 10.minutes.from_now)
  end

  def create_viewer_session
    viewer = ControlPlaneUser.create!(
      email: "cms-viewer-#{SecureRandom.hex(5)}@example.test",
      password: password,
      role: "viewer",
      status: "active",
      mfa_secret: ROTP::Base32.random_base32,
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

    @admin.exec("DELETE FROM control_plane_content_versions")
    @admin.exec("DELETE FROM control_plane_content_documents")
    @admin.exec("DELETE FROM control_plane_feature_flags")
    @admin.exec("DELETE FROM control_plane_audit_events")
    @admin.exec("DELETE FROM control_plane_sessions")
    @admin.exec("DELETE FROM control_plane_users")
  rescue PG::UndefinedTable
    nil
  end
end
