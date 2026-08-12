require "rails_helper"
require "securerandom"

RSpec.describe TenantScope do
  let(:tenant_a_id) { SecureRandom.uuid }
  let(:tenant_b_id) { SecureRandom.uuid }

  before do
    described_class.with(tenant_a_id) do
      Tenant.create!(id: tenant_a_id, name: "Tenant A", slug: "tenant-a-#{tenant_a_id}")
      Store.create!(tenant_id: tenant_a_id, name: "Store A", slug: "store-a")
    end

    described_class.with(tenant_b_id) do
      Tenant.create!(id: tenant_b_id, name: "Tenant B", slug: "tenant-b-#{tenant_b_id}")
      Store.create!(tenant_id: tenant_b_id, name: "Store B", slug: "store-b")
    end
  end

  after do
    [tenant_a_id, tenant_b_id].each do |tenant_id|
      described_class.with(tenant_id) do
        Store.delete_all
        Membership.delete_all
        Tenant.delete_all
      end
    end
    Current.reset
  end

  it "returns no tenant rows without an active tenant context" do
    expect(Tenant.where(id: [tenant_a_id, tenant_b_id]).count).to eq(0)
    expect(Store.where(tenant_id: [tenant_a_id, tenant_b_id]).count).to eq(0)
  end

  it "allows tenant A to see only tenant A rows" do
    described_class.with(tenant_a_id) do
      expect(Tenant.pluck(:id)).to contain_exactly(tenant_a_id)
      expect(Store.pluck(:tenant_id)).to contain_exactly(tenant_a_id)
      expect(Store.find_by(tenant_id: tenant_b_id)).to be_nil
    end
  end

  it "allows tenant B to see only tenant B rows" do
    described_class.with(tenant_b_id) do
      expect(Tenant.pluck(:id)).to contain_exactly(tenant_b_id)
      expect(Store.pluck(:tenant_id)).to contain_exactly(tenant_b_id)
      expect(Store.find_by(tenant_id: tenant_a_id)).to be_nil
    end
  end

  it "blocks cross-tenant writes even when application code supplies another tenant id" do
    expect do
      described_class.with(tenant_a_id) do
        Store.create!(tenant_id: tenant_b_id, name: "Forbidden", slug: "forbidden")
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "clears the tenant context after the scoped transaction" do
    described_class.with(tenant_a_id) { expect(Current.tenant_id).to eq(tenant_a_id) }
    expect(Current.tenant_id).to be_nil
  end
end
