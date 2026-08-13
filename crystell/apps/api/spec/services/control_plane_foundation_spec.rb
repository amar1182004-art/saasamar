require "rails_helper"
require "pg"
require "rotp"
require "securerandom"

RSpec.describe "Control plane foundation" do
  let(:password) { "Crystell-Control-Plane-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    cleanup_control_plane
    ControlPlaneCurrent.reset
  end

  after do
    cleanup_control_plane
    @admin&.close
    ControlPlaneCurrent.reset
  end

  it "uses a dedicated database login with no merchant table access" do
    expect(ControlPlaneRecord.connection.select_value("SELECT current_user")).to eq("crystell_control_app")

    expect {
      ControlPlaneRecord.connection.select_value("SELECT COUNT(*) FROM tenants")
    }.to raise_error(ActiveRecord::StatementInvalid, /permission denied for table tenants/)

    expect {
      ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM control_plane_users")
    }.to raise_error(ActiveRecord::StatementInvalid, /permission denied for table control_plane_users/)
  end

  it "bootstraps one encrypted-MFA owner and writes immutable audit history" do
    result = ControlPlane::BootstrapOwner.call(
      email: "owner-#{unique}@example.test",
      password: password
    )

    expect(result.user.role).to eq("owner")
    expect(result.user.mfa_enabled?).to be(true)
    expect(result.user.mfa_secret_ciphertext).not_to include(result.mfa_secret)
    expect(ControlPlaneAuditEvent.where(action: "control_plane.owner_bootstrapped").count).to eq(1)

    expect {
      ControlPlane::BootstrapOwner.call(
        email: "second-#{unique}@example.test",
        password: password
      )
    }.to raise_error(ControlPlane::BootstrapOwner::AlreadyBootstrappedError)

    expect {
      ControlPlaneAuditEvent.first.update!(reason: "tampered")
    }.to raise_error(ActiveRecord::StatementInvalid, /(permission denied|control_plane_audit_events_are_append_only)/)
  end

  it "requires password and MFA before issuing a short-lived independent session" do
    bootstrapped = ControlPlane::BootstrapOwner.call(
      email: "auth-#{unique}@example.test",
      password: password
    )
    otp = ROTP::TOTP.new(bootstrapped.mfa_secret).now

    result = ControlPlane::Authenticator.call(
      email: bootstrapped.user.email,
      password: password,
      otp: otp,
      ip_address: "203.0.113.10",
      user_agent: "Crystell Test"
    )

    expect(result.token).to be_present
    expect(result.session.token_digest).not_to eq(result.token)
    expect(result.session.mfa_verified_at).to be_present
    expect(result.session.active?).to be(true)
    expect(ControlPlaneAuditEvent.where(action: "control_plane.session_created").count).to eq(1)

    authenticated = ControlPlane::SessionAuthenticator.call(token: result.token)
    expect(authenticated.user.id).to eq(bootstrapped.user.id)
    expect(ControlPlaneCurrent.user.id).to eq(bootstrapped.user.id)

    ControlPlaneCurrent.reset
    expect {
      ControlPlane::Authenticator.call(
        email: bootstrapped.user.email,
        password: password,
        otp: otp
      )
    }.to raise_error(ControlPlane::Authenticator::AuthenticationError)
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
