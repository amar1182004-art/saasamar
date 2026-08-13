require "rotp"

module ControlPlane
  class BootstrapOwner
    class AlreadyBootstrappedError < StandardError; end

    Result = Data.define(:user, :mfa_secret)

    def self.call(email:, password:, mfa_secret: nil, now: Time.current)
      secret = mfa_secret.to_s.presence || ROTP::Base32.random_base32
      user = nil

      ControlPlaneRecord.transaction do
        raise AlreadyBootstrappedError, "control plane is already bootstrapped" if ControlPlaneUser.exists?

        user = ControlPlaneUser.create!(
          email: email,
          password: password,
          password_confirmation: password,
          status: "active",
          role: "owner",
          mfa_secret: secret,
          mfa_enabled_at: now
        )

        AuditWriter.call(
          action: "control_plane.owner_bootstrapped",
          user: user,
          target_type: "ControlPlaneUser",
          target_id: user.id,
          reason: "initial_bootstrap"
        )
      end

      Result.new(user: user, mfa_secret: secret)
    end
  end
end
