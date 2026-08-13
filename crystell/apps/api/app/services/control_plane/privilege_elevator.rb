require "rotp"

module ControlPlane
  class PrivilegeElevator
    class VerificationError < StandardError; end

    def self.call(password:, otp:, ip_address: nil, now: Time.current)
      user = ControlPlaneCurrent.user
      session = ControlPlaneCurrent.session
      raise VerificationError, "control plane session is required" unless user && session&.active?

      Permission.require!(user, "platform.manage")
      raise VerificationError, "privilege verification failed" unless user.authenticate(password.to_s)

      timestep = ROTP::TOTP.new(user.mfa_secret, issuer: "Crystell Control Plane").verify(
        otp.to_s,
        drift_behind: 30,
        drift_ahead: 30,
        after: user.last_mfa_timestep
      )
      raise VerificationError, "privilege verification failed" unless timestep

      ttl_minutes = Integer(ENV.fetch("CONTROL_PLANE_ELEVATION_TTL_MINUTES", "10"))

      ControlPlaneRecord.transaction do
        locked_user = ControlPlaneUser.lock.find(user.id)
        if locked_user.last_mfa_timestep.present? && timestep <= locked_user.last_mfa_timestep
          raise VerificationError, "privilege verification failed"
        end

        locked_user.update!(last_mfa_timestep: timestep)
        locked_session = ControlPlaneSession.lock.find(session.id)
        locked_session.update!(privilege_elevated_until: now + ttl_minutes.minutes)

        ControlPlaneCurrent.user = locked_user
        ControlPlaneCurrent.session = locked_session
        AuditWriter.call(
          action: "control_plane.privilege_elevated",
          user: locked_user,
          session: locked_session,
          target_type: "ControlPlaneSession",
          target_id: locked_session.id,
          ip_address: ip_address
        )
      end

      ControlPlaneCurrent.session
    rescue ROTP::Base32::Base32Error, ArgumentError, ControlPlane::CredentialVault::DecryptionError
      raise VerificationError, "privilege verification failed"
    end
  end
end
