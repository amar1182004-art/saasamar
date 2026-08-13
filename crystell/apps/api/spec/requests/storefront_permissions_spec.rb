require "rails_helper"
require "securerandom"

RSpec.describe "Storefront configuration API permissions", type: :request do
  let(:password) { "Crystell-Storefront-API-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @owner_registration = Auth::AccountRegistration.call(
      email: "storefront-api-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Storefront API Tenant #{unique}",
      tenant_slug: "storefront-api-tenant-#{unique}",
      store_name: "Storefront API Store #{unique}",
      store_slug: "storefront-api-store-#{unique}"
    )
    @member_registration = Auth::AccountRegistration.call(
      email: "storefront-api-member-#{unique}@example.test",
      password: password,
      tenant_name: "Storefront Member Personal #{unique}",
      tenant_slug: "storefront-member-personal-#{unique}",
      store_name: "Storefront Member Personal Store #{unique}",
      store_slug: "storefront-member-personal-store-#{unique}"
    )
    @foreign_registration = Auth::AccountRegistration.call(
      email: "storefront-api-foreign-#{unique}@example.test",
      password: password,
      tenant_name: "Storefront Foreign #{unique}",
      tenant_slug: "storefront-foreign-#{unique}",
      store_name: "Storefront Foreign Store #{unique}",
      store_slug: "storefront-foreign-store-#{unique}"
    )

    @owner = IdentityScope.with(@owner_registration.user_id) { User.find(@owner_registration.user_id) }
    @member = IdentityScope.with(@member_registration.user_id) { User.find(@member_registration.user_id) }
    @foreign_owner = IdentityScope.with(@foreign_registration.user_id) { User.find(@foreign_registration.user_id) }

    invitation = nil
    TenantAccess.with(user: @owner, tenant_id: @owner_registration.tenant_id) do
      invitation = Auth::TenantInvitationIssuer.call(email: @member.email, role: "member")
      @store = Store.find_by!(slug: "storefront-api-store-#{unique}")
    end
    Auth::TenantInvitationAcceptor.call(user: @member, token: invitation.token)

    TenantAccess.with(user: @foreign_owner, tenant_id: @foreign_registration.tenant_id) do
      @foreign_store = Store.find_by!(slug: "storefront-foreign-store-#{unique}")
    end

    @owner_token = Auth::SessionIssuer.call(user_id: @owner.id).token
    @member_token = Auth::SessionIssuer.call(user_id: @member.id).token
  end

  after do
    Current.reset
  end

  it "lets members read defaults while only managers can update and publish" do
    get storefront_path, headers: headers(@member_token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("storefront", "status")).to eq("offline")

    patch storefront_path,
          params: { storefront: { config: { theme_key: "member-forbidden" } } },
          headers: headers(@member_token)
    expect(response).to have_http_status(:forbidden)

    patch storefront_path,
          params: {
            storefront: {
              status: "online",
              config: {
                theme_key: "api-modern",
                locale: "ar-EG",
                currency_code: "EGP",
                settings: { header: { sticky: true } }
              }
            }
          },
          headers: headers(@owner_token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("storefront", "draft_version")).to eq(1)

    post "#{storefront_path}/publish", headers: headers(@owner_token)
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body).fetch("storefront")
    expect(body.fetch("published_version")).to eq(1)
    expect(body.fetch("published_config")).to eq(body.fetch("draft_config"))
  end

  it "does not expose a foreign tenant store" do
    get "/v1/stores/#{@foreign_store.id}/storefront", headers: headers(@owner_token)
    expect(response).to have_http_status(:not_found)
  end

  it "requires the trusted tenant context header" do
    get storefront_path, headers: {
      "Authorization" => "Bearer #{@owner_token}",
      "Accept" => "application/json"
    }

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body).fetch("error")).to eq("tenant_forbidden")
  end

  it "rejects unknown storefront keys instead of persisting arbitrary code" do
    patch storefront_path,
          params: { storefront: { config: { custom_javascript: "alert(1)" } } },
          headers: headers(@owner_token)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body).fetch("error")).to eq("storefront_validation_failed")
  end

  private

  def storefront_path
    "/v1/stores/#{@store.id}/storefront"
  end

  def headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "X-Crystell-Tenant" => @owner_registration.tenant_id,
      "Accept" => "application/json"
    }
  end
end
