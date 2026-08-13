module Control
  module V1
    class AuditEventsController < BaseController
      def index
        query = request.query_parameters
        result = ControlPlane::AuditLog.call(
          action: query["action"],
          actor_id: query["actor_id"],
          target_type: query["target_type"],
          target_id: query["target_id"],
          limit: query["limit"],
          offset: query["offset"],
          request_id: request.request_id,
          ip_address: request.remote_ip
        )

        render json: {
          audit_events: result.events.map { |event| serialize_event(event) },
          pagination: {
            has_more: result.has_more,
            next_offset: result.next_offset
          }
        }
      rescue ControlPlane::Permission::ForbiddenError
        render json: { error: "control_plane_forbidden" }, status: :forbidden
      rescue ActiveRecord::StatementInvalid => error
        raise unless error.cause.is_a?(PG::InvalidTextRepresentation)

        render json: { error: "invalid_audit_filter" }, status: :unprocessable_entity
      end

      private

      def serialize_event(event)
        {
          id: event.id,
          action: event.action,
          actor: event.control_plane_user && {
            id: event.control_plane_user.id,
            email: event.control_plane_user.email,
            role: event.control_plane_user.role
          },
          target: {
            type: event.target_type,
            id: event.target_id
          },
          request_id: event.request_id,
          ip_fingerprint: event.ip_hash,
          reason: event.reason,
          metadata: ControlPlane::AuditLog.sanitize_metadata(event.metadata),
          occurred_at: event.occurred_at
        }
      end
    end
  end
end
