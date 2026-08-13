require "rails_helper"
require "securerandom"

RSpec.describe "Tenant invitation and ownership security" do
  it "binds invitations to the invited identity and transfers ownership atomically" do
    unique = SecureRandom.hex(8)
    password = "Crystell-Invitation-Test-2026!"

    owner_registration = Auth::AccountRegistration.call(
      email: "owner-#{unique}@example.test",
      password: password,
      tenant_name: "Owner Tenant #{unique}",
      tenant_slug: "owner-tenant-#{unique}",
      store_name: "Owner Store #{unique}",
      store_slug: "owner-store-#{unique}"
    )

    invited_registration = Auth::AccountRegistration.call(
      email: "invited-#{unique}@example.test",
      password: password,
      tenant_name: "Invited Personal Tenant #{unique}",
      tenant_slug: "invited-personal-#{unique}",
      store_name: "Invited Personal Store #{unique}",
      store_slug: "invited-personal-store-#{unique}"
    )

    wrong_registration = Auth::AccountRegistration.call(
      email: "wrong-#{unique}@example.test",
      password: password,
      tenant_name: "Wrong Tenant #{unique}",
      tenant_slug: "wrong-tenant-#{unique}",
      store_name: "Wrong Store #{unique}",
      store_slug: "wrong-store-#{unique}"
    )

    owner = IdentityScope.with(owner_registration.user_id) { User.find(owner_registration.user_id) }
    invited_user = IdentityScope.with(invited_registration.user_id) { User.find(invited_registration.user_id) }
    wrong_user = IdentityScope.with(wrong_registration.user_id) { User.find(wrong_registration.user_id) }

    invitation = TenantAccess.with(user: owner, tenant_id: owner_registration.tenant_id) do |membership|
      expect(membership.role).to eq("owner")
      Auth::TenantInvitationIssuer.call(email: invited_user.email, role: "admin")
    end

    expect do
      Auth::TenantInvitationAcceptor.call(user: wrong_user, token: invitation.token)
    end.to raise_error(Auth::TenantInvitationAcceptor::InvalidInvitationError)

    accepted = Auth::TenantInvitationAcceptor.call(user: invited_user, token: invitation.token)
    expect(accepted.tenant_id).to eq(owner_registration.tenant_id)

    expect do
      Auth::TenantInvitationAcceptor.call(user: invited_user, token: invitation.token)
    end.to raise_error(Auth::TenantInvitationAcceptor::InvalidInvitationError)

    target_membership_id = TenantScope.with(owner_registration.tenant_id) do
      membership = Membership.find_by!(user_id: invited_user.id)
      expect(membership.role).to eq("admin")
      expect(membership.status).to eq("active")
      membership.id
    end

    TenantAccess.with(user: owner, tenant_id: owner_registration.tenant_id) do |membership|
      expect(membership.role).to eq("owner")
      result = TenantOwnershipTransfer.call(target_membership_id: target_membership_id)
      expect(result.target_user_id).to eq(invited_user.id)
    end

    TenantScope.with(owner_registration.tenant_id) do
      memberships = Membership.where(status: "active").order(:user_id).to_a
      expect(memberships.count { |membership| membership.role == "owner" }).to eq(1)
      expect(Membership.find_by!(user_id: invited_user.id).role).to eq("owner")
      expect(Membership.find_by!(user_id: owner.id).role).to eq("admin")
    end

    expect do
      TenantAccess.with(user: owner, tenant_id: owner_registration.tenant_id) do
        TenantOwnershipTransfer.call(target_membership_id: target_membership_id)
      end
    end.to raise_error(TenantPermission::ForbiddenError)
  end
end
