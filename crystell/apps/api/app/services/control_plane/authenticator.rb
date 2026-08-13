require "digest"
require "rotp"
require "securerandom"

module ControlPlane
  class Authenticator
    class AuthenticationError < StandardError; end
    class AccountLockedError < StandardError; end

    Result = Data.define(:user, :session, :token)

    def self.call(email:, password:, otp:, ip_address: nil, user_agent: nil, now: Time.current)
      normalized_email = email.to_s.strip.downcase
      user = ControlPlaneUser.find_by(email: normalized_email)

      if user&.locked_until.present? && user.locked_until > now
        audit_failure(user, ip_address, "account_locked")
        raise AccountLockedError, "control plane account is locked"
      end

      unless user&.status == "active" && user.authenticate(password.to_s) && user.mfa_enabled?
        record_failure!(user, now)
        audit_failure(user, ip_address, "invalid_credentials")
        raise AuthenticationError, "invalid control plane credentials"
      end

      timestep = verify_mfa(user, otp)
      unless timestep
        record_failure!(user, now)
        audit_failure(user, ip_address, "invalid_mfa")
        raise AuthenticationError, "invalid control plane credentials"
      end

      token = SecureRandom.urlsafe_base64(48)
      token_digest = Digest::SHA256.hexdigest(token)
      ttl_minutes = Integer(ENV.fetch("CONTROL_PLANE_SESSION_TTL_MINUTES", "60"))
      session = nil

      ControlPlaneRecord.transaction do
        locked_user = ControlPlaneUser.lock.find(user.id)
        if locked_user.last_mfa_timestep.present? && timestep <= locked_user.last_mfa_timestep
          record_failure!(locked_user, now)
          audit_failure(locked_user, ip_address, "replayed_mfa")
          raise AuthenticationError, "invalid control plane credentials"
        end

        locked_user.update!(
          failed_login_attempts: 0,
          locked_until: nil,
          last_authenticated_at: now,
          last_mfa_timestep: timestep
        )

        session = ControlPlaneSession.create!(
          control_plane_user_id: locked_user.id,
          token_digest: token_digest,
          expires_at: now + ttl_minutes.minutes,
          mfa_verified_at: now,
          ip_hash: ip_address.present? ? CredentialVault.fingerprint(ip_address.to_s, purpose: "control-plane-ip") : nil,
          user_agent: user_agent.to_s.first(1_000).presence,
          last_seen_at: now
        )

        AuditWriter.call(
          action: "control_plane.session_created",
          user: locked_user,
          session: session,
          target_type: "ControlPlaneSession",
          target_id: session.id,
          ip_address: ip_address
        )
        user = locked_user
      end

      Result.new(user: user, session: session, token: token)
    end

    def self.verify_mfa(user, otp)
      ROTP::TOTP.new(user.mfa_secret, issuer: "Crystell Control Plane").verify(
        otp.to_s,
        drift_behind: 30,
        drift_ahead: 30,
        after: user.last_mfa_timestep
      )
    rescue ROTP::Base32::Base32Error, ArgumentError
      nil
    end
    private_class_method :verify_mfa

    def self.record_failure!(user, now)
      return unless user

      threshold = Integer(ENV.fetch("CONTROL_PLANE_LOCKOUT_THRESHOLD", "5"))
      lock_seconds = Integer(ENV.fetch("CONTROL_PLANE_LOCKOUT_SECONDS", "1800"))

      ControlPlaneRecord.transaction(requires_new: true) do
        locked_user = ControlPlaneUser.lock.find(user.id)
        attempts = locked_user.failed_login_attempts + 1
        locked_until = attempts >= threshold ? now + lock_seconds.seconds : locked_user.locked_until
        locked_user.update!(failed_login_attempts: attempts, locked_until: locked_until)
      end
    end
    private_class_method :record_failure!

    def self.audit_failure(user, ip_address, reason)
      AuditWriter.call(
        action: "control_plane.authentication_failed",
        user: user,
        target_type: "ControlPlaneUser",
        target_id: user&.id,
        ip_address: ip_address,
        reason: reason
      )
    rescue StandardError
      nil
    end
    private_class_method :audit_failure
  end
end
