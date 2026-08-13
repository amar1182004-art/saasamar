require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Billing API permissions", type: :request do
  let(:password) { "Crystell-Billing-API-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin_db = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))

    @owner_registration = Auth::AccountRegistration.call(
      email: "billing-api-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Billing API Tenant #{unique}",
      tenant_slug: "billing-api-tenant-#{unique}",
      store_name: "Billing API Store #{unique}",
      store_slug: "billing-api-store-#{unique}"
    )
    @admin_registration = Auth::AccountRegistration.call(
      email: "billing-api-admin-#{unique}@example.test",
      password: password,
      tenant_name: "Admin Personal #{unique}",
      tenant_slug: "admin-personal-#{unique}",
      store_name: "Admin Personal Store #{unique}",
      store_slug: "admin-personal-store-#{unique}"
    )
    @member_registration = Auth::AccountRegistration.call(
      email: "billing-api-member-#{unique}@example.test",
      password: password,
      tenant_name: "Member Personal #{unique}",
      tenant_slug: "member-personal-#{unique}",
      store_name: "Member Personal Store #{unique}",
      store_slug: "member-personal-store-#{unique}"
    )

    @owner = IdentityScope.with(@owner_registration.user_id) { User.find(@owner_registration.user_id) }
    @admin_user = IdentityScope.with(@admin_registration.user_id) { User.find(@admin_registration.user_id) }
    @member_user = IdentityScope.with(@member_registration.user_id) { User.find(@member_registration.user_id) }

    admin_invitation = nil
    member_invitation = nil
    TenantAccess.with(user: @owner, tenant_id: @owner_registration.tenant_id) do
      admin_invitation = Auth::TenantInvitationIssuer.call(email: @admin_user.email, role: "admin")
      member_invitation = Auth::TenantInvitationIssuer.call(email: @member_user.email, role: "member")
    end
    Auth::TenantInvitationAcceptor.call(user: @admin_user, token: admin_invitation.token)
    Auth::TenantInvitationAcceptor.call(user: @member_user, token: member_invitation.token)

    @owner_token = Auth::SessionIssuer.call(user_id: @owner.id).token
    @admin_token = Auth::SessionIssuer.call(user_id: @admin_user.id).token
    @member_token = Auth::SessionIssuer.call(user_id: @member_user.id).token

    @plan_id = SecureRandom.uuid
    @price_id = SecureRandom.uuid
    @admin_db.exec_params(
      <<~SQL,
        INSERT INTO billing_plans (id, code, name, status, trial_days, public, metadata, created_at, updated_at)
        VALUES ($1::uuid, $2, $3, 'active', 0, true, '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      [@plan_id, "billing-api-plan-#{unique}", "Billing API Plan #{unique}"]
    )
    @admin_db.exec_params(
      <<~SQL,
        INSERT INTO billing_prices (id, billing_plan_id, currency, interval, amount_cents, status, created_at, updated_at)
        VALUES ($1::uuid, $2::uuid, 'EGP', 'monthly', 15000, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      [@price_id, @plan_id]
    )
  end

  after do
    @admin_db&.close
    Current.reset
  end

  it "allows owners to manage billing, admins to read it, and blocks members from billing endpoints" do
    post "/v1/billing/subscription",
         params: { price_id: @price_id },
         headers: headers(@owner_token)
    expect(response).to have_http_status(:created)

    get "/v1/billing/subscription", headers: headers(@admin_token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("subscription", "plan", "id")).to eq(@plan_id)

    delete "/v1/billing/subscription", headers: headers(@admin_token)
    expect(response).to have_http_status(:forbidden)

    get "/v1/billing/invoices", headers: headers(@member_token)
    expect(response).to have_http_status(:forbidden)

    delete "/v1/billing/subscription", headers: headers(@owner_token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("subscription", "cancel_at_period_end")).to be(true)

    post "/v1/billing/subscription/resume", headers: headers(@owner_token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("subscription", "cancel_at_period_end")).to be(false)
  end

  it "rejects tenant-scoped billing access without the trusted tenant context header" do
    get "/v1/billing/subscription", headers: {
      "Authorization" => "Bearer #{@owner_token}",
      "Accept" => "application/json"
    }

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body).fetch("error")).to eq("tenant_forbidden")
  end

  private

  def headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "X-Crystell-Tenant" => @owner_registration.tenant_id,
      "Accept" => "application/json"
    }
  end
end
