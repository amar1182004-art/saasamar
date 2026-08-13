module Auth
  class MfaManagement
    class NotEnabledError < StandardError; end

    def self.regenerate_recovery_codes!(user:, current_session_id:, password:, code: nil, recovery_code: nil)
      ensure_enabled!(user)
      SensitiveReauthentication.verify!(
        user: user,
        password: password,
        code: code,
        recovery_code: recovery_code
      )

      IdentityScope.with(user.id) do
        credential = MfaCredential.find_by!(user_id: user.id)
        recovery_codes = RecoveryCodes.generate
        credential.update!(recovery_code_digests: RecoveryCodes.digests(recovery_codes))
        revoke_other_sessions!(user.id, current_session_id)
        SecurityAudit.record!("auth.mfa_recovery_codes_regenerated")
        recovery_codes
      end
    end

    def self.disable!(user:, current_session_id:, password:, code: nil, recovery_code: nil)
      ensure_enabled!(user)
      SensitiveReauthentication.verify!(
        user: user,
        password: password,
        code: code,
        recovery_code: recovery_code
      )

      IdentityScope.with(user.id) do
        MfaCredential.find_by!(user_id: user.id).destroy!
        user.reload.update!(mfa_enabled: false)
        revoke_other_sessions!(user.id, current_session_id)
        SecurityAudit.record!("auth.mfa_disabled")
      end

      true
    end

    def self.ensure_enabled!(user)
      raise NotEnabledError, "MFA is not enabled" unless user.reload.mfa_enabled?
    end
    private_class_method :ensure_enabled!

    def self.revoke_other_sessions!(user_id, current_session_id)
      Session.where(user_id: user_id, revoked_at: nil)
        .where.not(id: current_session_id)
        .update_all(revoked_at: Time.current, updated_at: Time.current)
    end
    private_class_method :revoke_other_sessions!
  end
end
