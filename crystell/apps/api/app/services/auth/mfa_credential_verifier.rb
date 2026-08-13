module Auth
  class MfaCredentialVerifier
    def self.verify!(user_id:, code: nil, recovery_code: nil)
      IdentityScope.with(user_id) do
        credential = MfaCredential.find_by(user_id: user_id)
        return false unless credential&.confirmed?

        if recovery_code.present?
          verify_recovery_code!(credential, recovery_code)
        else
          verify_totp!(credential, code)
        end
      end
    end

    def self.verify_totp!(credential, code)
      return false if code.blank?

      secret = MfaCipher.decrypt(credential.encrypted_secret)
      verified_at = ROTP::TOTP.new(secret).verify(
        code.to_s,
        drift_behind: 30,
        drift_ahead: 30,
        after: credential.last_totp_at
      )
      return false unless verified_at

      credential.update!(last_totp_at: verified_at, last_used_at: Time.current)
      true
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      false
    end
    private_class_method :verify_totp!

    def self.verify_recovery_code!(credential, recovery_code)
      digest = RecoveryCodes.digest(recovery_code)
      digests = Array(credential.recovery_code_digests)
      index = digests.index do |stored|
        stored.bytesize == digest.bytesize && ActiveSupport::SecurityUtils.secure_compare(stored, digest)
      end
      return false unless index

      digests.delete_at(index)
      credential.update!(recovery_code_digests: digests, last_used_at: Time.current)
      true
    end
    private_class_method :verify_recovery_code!
  end
end
