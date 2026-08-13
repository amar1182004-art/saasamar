require "rails_helper"
require "securerandom"

RSpec.describe "Category hierarchy" do
  let(:password) { "Crystell-Category-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    registration = Auth::AccountRegistration.call(
      email: "category-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Category Tenant #{unique}",
      tenant_slug: "category-tenant-#{unique}",
      store_name: "Category Store #{unique}",
      store_slug: "category-store-#{unique}"
    )

    @tenant_id = registration.tenant_id
    @owner = IdentityScope.with(registration.user_id) { User.find(registration.user_id) }

    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      @store = Store.find_by!(slug: "category-store-#{unique}")
    end
  end

  after do
    Current.reset
  end

  it "allows a normal hierarchy and rejects multi-level cycles at PostgreSQL" do
    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      root = Category.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        name: "Root",
        slug: "root-#{unique}"
      )
      child = Category.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        parent_id: root.id,
        name: "Child",
        slug: "child-#{unique}"
      )
      grandchild = Category.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        parent_id: child.id,
        name: "Grandchild",
        slug: "grandchild-#{unique}"
      )

      expect do
        root.update!(parent_id: grandchild.id)
      end.to raise_error(ActiveRecord::StatementInvalid, /category hierarchy cycle detected/i)

      expect(root.reload.parent_id).to be_nil
      expect(child.reload.parent_id).to eq(root.id)
      expect(grandchild.reload.parent_id).to eq(child.id)
    end
  end

  it "rejects self-parenting at PostgreSQL" do
    TenantAccess.with(user: @owner, tenant_id: @tenant_id) do
      category = Category.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        name: "Self",
        slug: "self-#{unique}"
      )

      expect do
        category.update!(parent_id: category.id)
      end.to raise_error(ActiveRecord::StatementInvalid, /category cannot be its own parent/i)
    end
  end
end
