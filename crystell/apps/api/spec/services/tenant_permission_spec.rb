require "rails_helper"

RSpec.describe TenantPermission do
  MembershipStub = Struct.new(:role, :status)

  it "gives owners ownership, billing, catalog and inventory management permissions" do
    membership = MembershipStub.new("owner", "active")

    expect(described_class.allowed?(membership, "ownership.transfer")).to be(true)
    expect(described_class.allowed?(membership, "billing.read")).to be(true)
    expect(described_class.allowed?(membership, "billing.manage")).to be(true)
    expect(described_class.allowed?(membership, "catalog.read")).to be(true)
    expect(described_class.allowed?(membership, "catalog.manage")).to be(true)
    expect(described_class.allowed?(membership, "inventory.read")).to be(true)
    expect(described_class.allowed?(membership, "inventory.manage")).to be(true)
  end

  it "allows admins to manage catalog and inventory without changing subscriptions" do
    membership = MembershipStub.new("admin", "active")

    expect(described_class.allowed?(membership, "stores.manage")).to be(true)
    expect(described_class.allowed?(membership, "billing.read")).to be(true)
    expect(described_class.allowed?(membership, "catalog.manage")).to be(true)
    expect(described_class.allowed?(membership, "inventory.manage")).to be(true)
    expect(described_class.allowed?(membership, "ownership.transfer")).to be(false)
    expect(described_class.allowed?(membership, "billing.manage")).to be(false)
  end

  it "limits members to read-only store, catalog and inventory access" do
    membership = MembershipStub.new("member", "active")

    expect(described_class.allowed?(membership, "stores.read")).to be(true)
    expect(described_class.allowed?(membership, "catalog.read")).to be(true)
    expect(described_class.allowed?(membership, "inventory.read")).to be(true)
    expect(described_class.allowed?(membership, "stores.manage")).to be(false)
    expect(described_class.allowed?(membership, "catalog.manage")).to be(false)
    expect(described_class.allowed?(membership, "inventory.manage")).to be(false)
    expect(described_class.allowed?(membership, "members.invite")).to be(false)
    expect(described_class.allowed?(membership, "billing.read")).to be(false)
    expect(described_class.allowed?(membership, "billing.manage")).to be(false)
  end

  it "denies suspended memberships regardless of role" do
    membership = MembershipStub.new("owner", "suspended")

    expect(described_class.allowed?(membership, "tenant.manage")).to be(false)
    expect do
      described_class.require!(membership, "stores.read")
    end.to raise_error(TenantPermission::ForbiddenError)
  end
end
