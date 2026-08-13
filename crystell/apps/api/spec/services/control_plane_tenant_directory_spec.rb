require "rails_helper"
require "pg"
require "rotp"
require "securerandom"

RSpec.describe "Control plane tenant directory" do
  let(:merchant_password) { "Crystell-Merchant-Directory-2026!" }
  let(:control_password) { "Crystell-Control-Directory-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    cleanup_control_plane

    @merchant = Auth::AccountRegistration.call(
      email: "directory-merchant-#{unique}@example.test",
      password: merchant_password,
      tenant_name: "Directory Tenant #{unique}",
      tenant_slug: "directory-tenant-#{unique}",
      store_name: "Directory Store #{unique}",
      store_slug: "directory-store-#{unique}"
    )

    @control = ControlPlane::BootstrapOwner.call(
      email: "directory-control-#{unique}@example.test",
      password: control_password
    )
    otp = ROTP::TOTP.new(@control.mfa_secret).now
    authenticated = ControlPlane::Authenticator.call(
      email: @control.user.email,
      password: control_password,
      otp: otp,
      ip_address: "203.0.113.50",
      user_agent: "Crystell Tenant Directory Spec"
    )
    ControlPlaneCurrent.user = authenticated.user
    ControlPlaneCurrent.session = authenticated.session
  end

  after do
    cleanup_control_plane
    @admin&.close
    ControlPlaneCurrent.reset
    Current.reset
  end

  it "returns only the safe tenant directory fields through the capability function" do
    expect {
      ControlPlaneRecord.connection.select_value("SELECT COUNT(*) FROM tenants")
    }.to raise_error(ActiveRecord::StatementInvalid, /permission denied for table tenants/)

    rows = ControlPlane::TenantDirectory.call(
      query: "directory-tenant-#{unique}",
      limit: 25,
      offset: 0,
      request_id: "directory-request-#{unique}",
      ip_address: "203.0.113.50"
    )

    expect(rows.length).to eq(1)
    row = rows.first
    expect(row.fetch("tenant_id")).to eq(@merchant.tenant_id)
    expect(row.fetch("tenant_slug")).to eq("directory-tenant-#{unique}")
    expect(row.keys).to match_array(%w[
      tenant_id
      tenant_name
      tenant_slug
      tenant_status
      stores_count
      active_stores_count
      created_at
    ])

    audit = ControlPlaneAuditEvent.find_by!(action: "control_plane.tenant_directory_viewed")
    expect(audit.request_id).to eq("directory-request-#{unique}")
    expect(audit.metadata.fetch("result_count")).to eq(1)
  end

  it "enforces bounded pagination" do
    rows = ControlPlane::TenantDirectory.call(
      query: "directory-tenant-#{unique}",
      limit: 10_000,
      offset: -20
    )

    expect(rows.length).to eq(1)
    audit = ControlPlaneAuditEvent.where(action: "control_plane.tenant_directory_viewed").order(:occurred_at).last
    expect(audit.metadata.fetch("limit")).to eq(100)
    expect(audit.metadata.fetch("offset")).to eq(0)
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
