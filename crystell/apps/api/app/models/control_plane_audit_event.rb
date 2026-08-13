class ControlPlaneAuditEvent < ControlPlaneRecord
  self.table_name = "control_plane_audit_events"

  belongs_to :control_plane_user, optional: true
  belongs_to :control_plane_session, optional: true

  validates :action, presence: true, length: { minimum: 3, maximum: 120 }
end
