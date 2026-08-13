module Control
  module V1
    class SupportTicketsController < BaseController
      def index
        rows = ControlPlane::SupportDesk.list(
          status: params[:status],
          query: params[:q],
          limit: params[:limit],
          offset: params[:offset],
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        render json: { support_tickets: rows.map { |row| serialize_ticket(row) } }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::SupportDesk::InvalidSupportRequestError => error
        render_invalid(error)
      end

      def show
        rows = ControlPlane::SupportDesk.thread(
          ticket_id: params.require(:id),
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        first = rows.first
        render json: {
          support_ticket: serialize_ticket(first).merge(
            messages: rows.filter_map { |row| serialize_message(row) if row["message_id"].present? }
          )
        }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::SupportDesk::NotFoundError
        render_not_found
      end

      def reply
        message_id = ControlPlane::SupportDesk.reply(
          ticket_id: params.require(:id),
          body: params.require(:body),
          reason: params.require(:reason),
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        render json: { support_message: { id: message_id } }, status: :created
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::SupportDesk::InvalidSupportRequestError, ActionController::ParameterMissing => error
        render_invalid(error)
      rescue ControlPlane::SupportDesk::NotFoundError
        render_not_found
      end

      def update
        ControlPlane::SupportDesk.transition(
          ticket_id: params.require(:id),
          status: params.require(:status),
          reason: params.require(:reason),
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        render json: { updated: true }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::SupportDesk::InvalidSupportRequestError, ActionController::ParameterMissing => error
        render_invalid(error)
      rescue ControlPlane::SupportDesk::NotFoundError
        render_not_found
      end

      def attachment
        preview = ControlPlane::SupportDesk.attachment_preview(
          ticket_id: params.require(:ticket_id),
          attachment_id: params.require(:id),
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        render json: preview
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::SupportDesk::NotFoundError
        render_not_found
      end

      private

      def serialize_ticket(row)
        {
          id: row.fetch("ticket_id"),
          tenant: { id: row.fetch("tenant_id"), name: row.fetch("tenant_name") },
          store: { id: row.fetch("store_id"), name: row.fetch("store_name") },
          ticket_number: row.fetch("ticket_number"),
          subject: row.fetch("subject"),
          priority: row.fetch("priority"),
          status: row.fetch("ticket_status"),
          source: row.fetch("source"),
          last_message_at: row["last_message_at"],
          created_at: row["created_at"]
        }
      end

      def serialize_message(row)
        {
          id: row.fetch("message_id"),
          author_type: row.fetch("author_type"),
          author_label: row.fetch("author_label"),
          body: row.fetch("message_body"),
          created_at: row.fetch("message_created_at"),
          attachments: row.fetch("message_attachments", [])
        }
      end

      def render_forbidden
        render json: { error: "control_plane_forbidden" }, status: :forbidden
      end

      def render_invalid(error)
        render json: { error: "support_request_invalid", details: error.message }, status: :unprocessable_entity
      end

      def render_not_found
        render json: { error: "support_ticket_not_found" }, status: :not_found
      end
    end
  end
end
