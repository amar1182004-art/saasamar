module Auth
  class MfaEnrollment
    class AlreadyEnabledError < StandardError; end
    class InvalidCodeError < StandardError; end

    Setup = Data.define(:secret, :provisioning_uri)
    Confirmation = Data.define(:recovery_codes)

    def self.begin_for(user)
      IdentityScope.with(user.id) do
        raise AlreadyEnabledError, "MFA is already enabled" if user.reload.mfa_enabled?

        secret = ROTP::Base32.random_base32
        credential = MfaCredential.find_or_initialize_by(user_id: user.id)
        credential.assign_attributes(
          encrypted_secret: MfaCipher.encrypt(secret),
          recovery_code_digests: [],
          confirmed_at: nil,
          last_totp_at: nil,
          last_used_at: nil
        )
        credential.save!

        totp = ROTP::TOTP.new(secret, issuer: "Crystell")
        Setup.new(
          secret: secret,
          provisioning_uri: totp.provisioning_uri(user.email)
        )
      end
    end

    def self.confirm!(user:, code:)
      IdentityScope.with(user.id) do
        user.reload
        raise AlreadyEnabledError, "MFA is already enabled" if user.mfa_enabled?

        credential = MfaCredential.find_by!(user_id: user.id)
        secret = MfaCipher.decrypt(credential.encrypted_secret)
        verified_at = ROTP::TOTP.new(secret).verify(
          code.to_s,
          drift_behind: 30,
          drift_ahead: 30,
          after: credential.last_totp_at
        )
        raise InvalidCodeError, "invalid MFA code" unless verified_at

        recovery_codes = RecoveryCodes.generate
        credential.update!(
          confirmed_at: Time.current,
          last_totp_at: verified_at,
          last_used_at: Time.current,
          recovery_code_digests: RecoveryCodes.digests(recovery_codes)
        )
        user.update!(mfa_enabled: true)
        SecurityAudit.record!("auth.mfa_enabled")

        Confirmation.new(recovery_codes: recovery_codes)
      end
    end
  end
end
