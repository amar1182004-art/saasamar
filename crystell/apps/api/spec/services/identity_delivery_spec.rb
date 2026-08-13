require "rails_helper"
require "securerandom"

RSpec.describe Auth::IdentityDelivery do
  it "uses verification/reset tokens once and revokes sessions after password reset" do
    unique = SecureRandom.hex(8)
    email = "identity-#{unique}@example.test"
    old_password = "Crystell-Identity-Old-2026!"
    new_password = "Crystell-Identity-New-2026!"

    registration = Auth::AccountRegistration.call(
      email: email,
      password: old_password,
      tenant_name: "Identity Tenant #{unique}",
      tenant_slug: "identity-tenant-#{unique}",
      store_name: "Identity Store #{unique}",
      store_slug: "identity-store-#{unique}"
    )

    verification = described_class.request(
      email: email,
      purpose: "email_verification"
    )
    expect(verification.queued).to be(true)
    expect(Auth::IdentityTokenConsumer.verify_email!(verification.token)).to be(true)
    expect(Auth::IdentityTokenConsumer.verify_email!(verification.token)).to be(false)

    IdentityScope.with(registration.user_id) do
      expect(User.find(registration.user_id).email_verified_at).to be_present
    end

    issued_session = Auth::SessionIssuer.call(user_id: registration.user_id)
    expect(Auth::SessionAuthenticator.call(issued_session.token)).to be_present

    reset = described_class.request(
      email: email,
      purpose: "password_reset"
    )
    expect(reset.queued).to be(true)
    expect(
      Auth::IdentityTokenConsumer.reset_password!(
        token: reset.token,
        password: new_password
      )
    ).to be(true)

    expect(Auth::IdentityTokenConsumer.reset_password!(token: reset.token, password: new_password)).to be(false)
    expect(Auth::SessionAuthenticator.call(issued_session.token)).to be_nil

    authenticated = Auth::PasswordAuthenticator.call(email: email, password: new_password)
    expect(authenticated&.user_id).to eq(registration.user_id)
    expect(Auth::PasswordAuthenticator.call(email: email, password: old_password)).to be_nil
  end
end
