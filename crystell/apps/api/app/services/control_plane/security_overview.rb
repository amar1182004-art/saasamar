module ControlPlane
  class SecurityOverview
    WINDOW = 24.hours

    def self.call(now: Time.current, request_id: nil, ip_address: nil)
      user = ControlPlaneCurrent.user
      Permission.require!(user, "security.read")

      active_sessions = ControlPlaneSession.where(revoked_at: nil).where("expires_at > ?", now)
      recent_events = ControlPlaneAuditEvent.where("occurred_at >= ?", now - WINDOW)

      result = {
        users: {
          total: ControlPlaneUser.count,
          active: ControlPlaneUser.where(status: "active").count,
          suspended: ControlPlaneUser.where(status: "suspended").count,
          locked: ControlPlaneUser.where("locked_until > ?", now).count,
          roles: ControlPlaneUser.group(:role).count
        },
        sessions: {
          active: active_sessions.count,
          elevated: active_sessions.where("privilege_elevated_until > ?", now).count
        },
        activity_24h: {
          audit_events: recent_events.count,
          authentication_failures: recent_events.where(action: "control_plane.authentication_failed").count,
          privilege_elevations: recent_events.where(action: "control_plane.privilege_elevated").count
        },
        generated_at: now
      }

      AuditWriter.call(
        action: "control_plane.security_overview_viewed",
        request_id: request_id,
        ip_address: ip_address
      )

      result
    end
  end
end
