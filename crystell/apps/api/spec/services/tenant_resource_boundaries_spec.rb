require "rails_helper"
require "securerandom"

RSpec.describe "Tenant resource boundaries" do
  let(:tenant_a_id) { SecureRandom.uuid }
  let(:tenant_b_id) { SecureRandom.uuid }
  let(:store_id) { SecureRandom.uuid }

  it "namespaces cache keys by tenant and rejects unsafe segments" do
    key_a = TenantCacheKey.build(
      tenant_id: tenant_a_id,
      namespace: "product",
      store_id
    )
    key_b = TenantCacheKey.build(
      tenant_id: tenant_b_id,
      namespace: "product",
      store_id
    )

    expect(key_a).to start_with("tenant:#{tenant_a_id}:")
    expect(key_b).to start_with("tenant:#{tenant_b_id}:")
    expect(key_a).not_to eq(key_b)

    expect do
      TenantCacheKey.build(tenant_id: "../escape", namespace: "product", store_id)
    end.to raise_error(TenantCacheKey::InvalidKeyError)
  end

  it "creates storage paths that cannot escape the tenant/store namespace" do
    path = TenantStorageKey.build(
      tenant_id: tenant_a_id,
      store_id: store_id,
      category: "documents",
      object_id: SecureRandom.uuid,
      filename: "../../customer-contract.pdf"
    )

    expect(path).to start_with("tenants/#{tenant_a_id}/stores/#{store_id}/documents/")
    expect(path).not_to include("..")
    expect(path).to end_with(".pdf")
  end

  it "requires a tenant id in every job envelope" do
    envelope = TenantJobEnvelope.build(
      tenant_id: tenant_a_id,
      store_id: store_id,
      payload: { "operation" => "refresh_catalog" }
    )

    expect(TenantJobEnvelope.validate!(envelope).fetch("tenant_id")).to eq(tenant_a_id)

    expect do
      TenantJobEnvelope.build(tenant_id: nil, payload: {})
    end.to raise_error(TenantJobEnvelope::InvalidEnvelopeError)
  end

  it "restores PostgreSQL tenant isolation before a background job executes" do
    TenantScope.with(tenant_a_id) do
      Tenant.create!(id: tenant_a_id, name: "Job Tenant A", slug: "job-a-#{tenant_a_id}")
      Store.create!(id: store_id, tenant_id: tenant_a_id, name: "Job Store", slug: "job-store")
    end

    TenantScope.with(tenant_b_id) do
      Tenant.create!(id: tenant_b_id, name: "Job Tenant B", slug: "job-b-#{tenant_b_id}")
    end

    envelope_a = TenantJobEnvelope.build(tenant_id: tenant_a_id, payload: { operation: "read" })
    envelope_b = TenantJobEnvelope.build(tenant_id: tenant_b_id, payload: { operation: "read" })

    count_a = TenantJobContext.with(envelope_a) { |_payload| Store.where(id: store_id).count }
    count_b = TenantJobContext.with(envelope_b) { |_payload| Store.where(id: store_id).count }

    expect(count_a).to eq(1)
    expect(count_b).to eq(0)
  ensure
    [tenant_a_id, tenant_b_id].each do |tenant_id|
      TenantScope.with(tenant_id) do
        Store.delete_all
        Tenant.delete_all
      end
    end
  end
end
