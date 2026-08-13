require "rails_helper"
require "securerandom"

RSpec.describe "Merchant dashboard API permissions", type: :request do
  let(:password) { "Crystell-Dashboard-API-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @owner_registration = Auth::AccountRegistration.call(
      email: "dashboard-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Dashboard Tenant #{unique}",
      tenant_slug: "dashboard-tenant-#{unique}",
      store_name: "Dashboard Store #{unique}",
      store_slug: "dashboard-store-#{unique}"
    )
    @member_registration = Auth::AccountRegistration.call(
      email: "dashboard-member-#{unique}@example.test",
      password: password,
      tenant_name: "Dashboard Member Personal #{unique}",
      tenant_slug: "dashboard-member-personal-#{unique}",
      store_name: "Dashboard Member Personal Store #{unique}",
      store_slug: "dashboard-member-personal-store-#{unique}"
    )
    @foreign_registration = Auth::AccountRegistration.call(
      email: "dashboard-foreign-#{unique}@example.test",
      password: password,
      tenant_name: "Dashboard Foreign #{unique}",
      tenant_slug: "dashboard-foreign-#{unique}",
      store_name: "Dashboard Foreign Store #{unique}",
      store_slug: "dashboard-foreign-store-#{unique}"
    )

    @owner = IdentityScope.with(@owner_registration.user_id) { User.find(@owner_registration.user_id) }
    @member = IdentityScope.with(@member_registration.user_id) { User.find(@member_registration.user_id) }
    @foreign_owner = IdentityScope.with(@foreign_registration.user_id) { User.find(@foreign_registration.user_id) }

    invitation = nil
    TenantAccess.with(user: @owner, tenant_id: @owner_registration.tenant_id) do
      invitation = Auth::TenantInvitationIssuer.call(email: @member.email, role: "member")
      @store = Store.find_by!(slug: "dashboard-store-#{unique}")
    end
    Auth::TenantInvitationAcceptor.call(user: @member, token: invitation.token)

    TenantAccess.with(user: @foreign_owner, tenant_id: @foreign_registration.tenant_id) do
      @foreign_store = Store.find_by!(slug: "dashboard-foreign-store-#{unique}")
    end

    @member_token = Auth::SessionIssuer.call(user_id: @member.id).token
    @owner_token = Auth::SessionIssuer.call(user_id: @owner.id).token
  end

  after do
    Current.reset
  end

  it "lets a tenant member read the scoped merchant summary" do
    get dashboard_path, headers: headers(@member_token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body).fetch("dashboard")
    expect(body.dig("store", "id")).to eq(@store.id)
    expect(body).to include("orders", "products", "inventory", "shipments", "recent_orders")
  end

  it "does not expose a foreign tenant store" do
    get "/v1/stores/#{@foreign_store.id}/dashboard", headers: headers(@owner_token)
    expect(response).to have_http_status(:not_found)
  end

  it "requires the trusted tenant context header" do
    get dashboard_path, headers: {
      "Authorization" => "Bearer #{@owner_token}",
      "Accept" => "application/json"
    }

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body).fetch("error")).to eq("tenant_forbidden")
  end

  private

  def dashboard_path
    "/v1/stores/#{@store.id}/dashboard"
  end

  def headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "X-Crystell-Tenant" => @owner_registration.tenant_id,
      "Accept" => "application/json"
    }
  end
end
