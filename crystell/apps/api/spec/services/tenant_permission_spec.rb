require "rails_helper"

RSpec.describe TenantPermission do
  MembershipStub = Struct.new(:role, :status)

  it "gives owners ownership and billing permissions" do
    membership = MembershipStub.new("owner", "active")

    expect(described_class.allowed?(membership, "ownership.transfer")).to be(true)
    expect(described_class.allowed?(membership, "billing.manage")).to be(true)
  end

  it "does not allow admins to transfer ownership or manage billing" do
    membership = MembershipStub.new("admin", "active")

    expect(described_class.allowed?(membership, "stores.manage")).to be(true)
    expect(described_class.allowed?(membership, "ownership.transfer")).to be(false)
    expect(described_class.allowed?(membership, "billing.manage")).to be(false)
  end

  it "limits members to store reads" do
    membership = MembershipStub.new("member", "active")

    expect(described_class.allowed?(membership, "stores.read")).to be(true)
    expect(described_class.allowed?(membership, "stores.manage")).to be(false)
    expect(described_class.allowed?(membership, "members.invite")).to be(false)
  end

  it "denies suspended memberships regardless of role" do
    membership = MembershipStub.new("owner", "suspended")

    expect(described_class.allowed?(membership, "tenant.manage")).to be(false)
    expect do
      described_class.require!(membership, "stores.read")
    end.to raise_error(TenantPermission::ForbiddenError)
  end
end
