require "rails_helper"
require "pg"
require "rotp"
require "securerandom"

RSpec.describe "Control plane tenant support overview" do
  let(:merchant_password) { "Crystell-Merchant-Support-2026!" }
  let(:control_password) { "Crystell-Control-Support-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    cleanup_control_plane

    @merchant = Auth::AccountRegistration.call(
      email: "support-merchant-#{unique}@example.test",
      password: merchant_password,
      tenant_name: "Support Tenant #{unique}",
      tenant_slug: "support-tenant-#{unique}",
      store_name: "Support Store #{unique}",
      store_slug: "support-store-#{unique}"
    )

    @control = ControlPlane::BootstrapOwner.call(
      email: "support-control-#{unique}@example.test",
      password: control_password
    )
    otp = ROTP::TOTP.new(@control.mfa_secret).now
    authenticated = ControlPlane::Authenticator.call(
      email: @control.user.email,
      password: control_password,
      otp: otp,
      ip_address: "203.0.113.60",
      user_agent: "Crystell Tenant Support Spec"
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

  it "returns operational aggregates through the capability function and audits access" do
    row = ControlPlane::TenantSupportOverview.call(
      tenant_id: @merchant.tenant_id,
      request_id: "support-request-#{unique}",
      ip_address: "203.0.113.60"
    )

    expect(row.fetch("tenant_id")).to eq(@merchant.tenant_id)
    expect(row.fetch("tenant_slug")).to eq("support-tenant-#{unique}")
    expect(row.keys).to match_array(%w[
      tenant_id
      tenant_name
      tenant_slug
      tenant_status
      stores_count
      active_stores_count
      orders_count
      paid_orders_count
      open_shipments_count
      products_count
      active_products_count
      subscription_status
      subscription_plan_code
      created_at
    ])
    expect(row.keys.grep(/credential|secret|password|token/)).to be_empty

    audit = ControlPlaneAuditEvent.find_by!(action: "control_plane.tenant_support_overview_viewed")
    expect(audit.target_id).to eq(@merchant.tenant_id)
    expect(audit.request_id).to eq("support-request-#{unique}")
  end

  it "rejects roles without tenant support permission" do
    ControlPlaneCurrent.user.update!(role: "viewer")

    expect {
      ControlPlane::TenantSupportOverview.call(tenant_id: @merchant.tenant_id)
    }.to raise_error(ControlPlane::Permission::ForbiddenError)
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
