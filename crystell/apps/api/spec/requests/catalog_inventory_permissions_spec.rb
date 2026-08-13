require "rails_helper"
require "securerandom"

RSpec.describe "Catalog and inventory API permissions", type: :request do
  let(:password) { "Crystell-Catalog-API-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @owner_registration = Auth::AccountRegistration.call(
      email: "catalog-api-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Catalog API Tenant #{unique}",
      tenant_slug: "catalog-api-tenant-#{unique}",
      store_name: "Catalog API Store #{unique}",
      store_slug: "catalog-api-store-#{unique}"
    )
    @admin_registration = Auth::AccountRegistration.call(
      email: "catalog-api-admin-#{unique}@example.test",
      password: password,
      tenant_name: "Catalog Admin Personal #{unique}",
      tenant_slug: "catalog-admin-personal-#{unique}",
      store_name: "Catalog Admin Personal Store #{unique}",
      store_slug: "catalog-admin-personal-store-#{unique}"
    )
    @member_registration = Auth::AccountRegistration.call(
      email: "catalog-api-member-#{unique}@example.test",
      password: password,
      tenant_name: "Catalog Member Personal #{unique}",
      tenant_slug: "catalog-member-personal-#{unique}",
      store_name: "Catalog Member Personal Store #{unique}",
      store_slug: "catalog-member-personal-store-#{unique}"
    )

    @owner = IdentityScope.with(@owner_registration.user_id) { User.find(@owner_registration.user_id) }
    @admin_user = IdentityScope.with(@admin_registration.user_id) { User.find(@admin_registration.user_id) }
    @member_user = IdentityScope.with(@member_registration.user_id) { User.find(@member_registration.user_id) }

    admin_invitation = nil
    member_invitation = nil
    TenantAccess.with(user: @owner, tenant_id: @owner_registration.tenant_id) do
      admin_invitation = Auth::TenantInvitationIssuer.call(email: @admin_user.email, role: "admin")
      member_invitation = Auth::TenantInvitationIssuer.call(email: @member_user.email, role: "member")
      @store = Store.find_by!(slug: "catalog-api-store-#{unique}")
    end
    Auth::TenantInvitationAcceptor.call(user: @admin_user, token: admin_invitation.token)
    Auth::TenantInvitationAcceptor.call(user: @member_user, token: member_invitation.token)

    TenantAccess.with(user: @admin_user, tenant_id: @admin_registration.tenant_id) do
      @foreign_store = Store.find_by!(slug: "catalog-admin-personal-store-#{unique}")
    end

    @owner_token = Auth::SessionIssuer.call(user_id: @owner.id).token
    @admin_token = Auth::SessionIssuer.call(user_id: @admin_user.id).token
    @member_token = Auth::SessionIssuer.call(user_id: @member_user.id).token
  end

  after do
    Current.reset
  end

  it "allows owner and admin catalog management while keeping members read-only" do
    post products_path,
         params: product_payload,
         headers: headers(@owner_token)
    expect(response).to have_http_status(:created)
    product = JSON.parse(response.body).fetch("product")
    expect(product.fetch("variants").length).to eq(1)

    get products_path, headers: headers(@member_token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("products").map { |item| item.fetch("id") }).to include(product.fetch("id"))

    post products_path,
         params: product_payload.merge(product: product_payload.fetch(:product).merge(slug: "member-forbidden-#{unique}")),
         headers: headers(@member_token)
    expect(response).to have_http_status(:forbidden)

    post products_path,
         params: product_payload.merge(product: product_payload.fetch(:product).merge(slug: "admin-created-#{unique}")),
         headers: headers(@admin_token)
    expect(response).to have_http_status(:created)
  end

  it "allows inventory management for admins, read access for members and no member mutations" do
    post products_path,
         params: product_payload,
         headers: headers(@owner_token)
    expect(response).to have_http_status(:created)
    variant_id = JSON.parse(response.body).dig("product", "variants", 0, "id")

    post inventory_locations_path,
         params: { location: { name: "Main Warehouse", code: "main-#{unique}" } },
         headers: headers(@admin_token)
    expect(response).to have_http_status(:created)
    location_id = JSON.parse(response.body).dig("location", "id")

    post inventory_adjustments_path,
         params: {
           inventory_location_id: location_id,
           product_variant_id: variant_id,
           delta_on_hand: 5,
           reason: "stock.received",
           idempotency_key: "api-adjust-#{unique}"
         },
         headers: headers(@admin_token)
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body).dig("adjustment", "available")).to eq(5)

    get inventory_levels_path,
        params: { product_variant_id: variant_id },
        headers: headers(@member_token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("levels", 0, "available")).to eq(5)

    post inventory_adjustments_path,
         params: {
           inventory_location_id: location_id,
           product_variant_id: variant_id,
           delta_on_hand: 1,
           reason: "member.forbidden",
           idempotency_key: "member-adjust-#{unique}"
         },
         headers: headers(@member_token)
    expect(response).to have_http_status(:forbidden)
  end

  it "does not expose a foreign-tenant store even when its id is supplied in the URL" do
    get "/v1/stores/#{@foreign_store.id}/catalog/products", headers: headers(@owner_token)

    expect(response).to have_http_status(:not_found)
  end

  it "requires the trusted tenant context header for catalog and inventory endpoints" do
    get products_path, headers: {
      "Authorization" => "Bearer #{@owner_token}",
      "Accept" => "application/json"
    }

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body).fetch("error")).to eq("tenant_forbidden")
  end

  private

  def products_path
    "/v1/stores/#{@store.id}/catalog/products"
  end

  def inventory_locations_path
    "/v1/stores/#{@store.id}/inventory/locations"
  end

  def inventory_levels_path
    "/v1/stores/#{@store.id}/inventory/levels"
  end

  def inventory_adjustments_path
    "/v1/stores/#{@store.id}/inventory/adjustments"
  end

  def product_payload
    {
      product: {
        title: "API Product #{unique}",
        slug: "api-product-#{unique}",
        status: "active"
      },
      variants: [
        {
          title: "Default",
          sku: "API-SKU-#{unique}",
          currency: "EGP",
          price_cents: 25_000
        }
      ]
    }
  end

  def headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "X-Crystell-Tenant" => @owner_registration.tenant_id,
      "Accept" => "application/json"
    }
  end
end
