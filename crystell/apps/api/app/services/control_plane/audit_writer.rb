module ControlPlane
  class AuditWriter
    def self.call(action:, user: ControlPlaneCurrent.user, session: ControlPlaneCurrent.session, target_type: nil, target_id: nil, request_id: nil, ip_address: nil, reason: nil, metadata: {})
      ControlPlaneAuditEvent.create!(
        control_plane_user_id: user&.id,
        control_plane_session_id: session&.id,
        action: action.to_s,
        target_type: target_type.to_s.presence,
        target_id: target_id.to_s.presence,
        request_id: request_id.to_s.presence,
        ip_hash: ip_address.present? ? CredentialVault.fingerprint(ip_address.to_s, purpose: "control-plane-ip") : nil,
        reason: reason.to_s.presence,
        metadata: metadata.to_h,
        occurred_at: Time.current
      )
    end
  end
end
