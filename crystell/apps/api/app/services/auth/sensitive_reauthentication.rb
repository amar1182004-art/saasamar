module Auth
  class SensitiveReauthentication
    class FailedError < StandardError; end

    def self.verify!(user:, password:, code: nil, recovery_code: nil)
      result = PasswordAuthenticator.call(email: user.email, password: password)
      raise FailedError, "reauthentication failed" unless result&.user_id == user.id
      raise FailedError, "reauthentication failed" if result.locked_until&.future?

      if user.mfa_enabled?
        verified = MfaCredentialVerifier.verify!(
          user_id: user.id,
          code: code,
          recovery_code: recovery_code
        )
        raise FailedError, "reauthentication failed" unless verified
      end

      true
    end
  end
end
