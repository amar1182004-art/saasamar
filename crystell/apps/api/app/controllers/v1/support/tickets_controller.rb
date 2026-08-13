module V1
  module Support
    class TicketsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        tickets = ::Support::TicketDesk.list(store_id: params.require(:store_id), status: params[:status])
        render json: { support_tickets: tickets.map { |ticket| serialize_ticket(ticket) } }
      rescue TenantPermission::ForbiddenError
        render_forbidden
      rescue ::Support::TicketDesk::InvalidTicketError => error
        render_invalid(error)
      end

      def show
        ticket = ::Support::TicketDesk.read(store_id: params.require(:store_id), ticket_id: params.require(:id))
        messages = SupportMessage.includes(:support_attachments).where(support_ticket_id: ticket.id).order(:created_at, :id)
        render json: {
          support_ticket: serialize_ticket(ticket).merge(
            messages: messages.map { |message| serialize_message(message) }
          )
        }
      rescue TenantPermission::ForbiddenError
        render_forbidden
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def create
        ticket = ::Support::TicketDesk.create(
          store_id: params.require(:store_id),
          subject: params.require(:subject),
          body: params.require(:body),
          priority: params.fetch(:priority, "normal")
        )
        render json: { support_ticket: serialize_ticket(ticket) }, status: :created
      rescue TenantPermission::ForbiddenError
        render_forbidden
      rescue ::Support::TicketDesk::InvalidTicketError, ActionController::ParameterMissing => error
        render_invalid(error)
      end

      def update
        ticket = ::Support::TicketDesk.transition(
          store_id: params.require(:store_id),
          ticket_id: params.require(:id),
          status: params.require(:status)
        )
        render json: { support_ticket: serialize_ticket(ticket) }
      rescue TenantPermission::ForbiddenError
        render_forbidden
      rescue ::Support::TicketDesk::InvalidTicketError, ActionController::ParameterMissing => error
        render_invalid(error)
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      private

      def serialize_ticket(ticket)
        {
          id: ticket.id,
          ticket_number: ticket.ticket_number,
          subject: ticket.subject,
          priority: ticket.priority,
          status: ticket.status,
          source: ticket.source,
          last_message_at: ticket.last_message_at,
          created_at: ticket.created_at
        }
      end

      def serialize_message(message)
        {
          id: message.id,
          author_type: message.author_type,
          body: message.body,
          created_at: message.created_at,
          attachments: message.support_attachments.select { |attachment| attachment.status == "ready" }.map do |attachment|
            {
              id: attachment.id,
              kind: attachment.kind,
              filename: attachment.filename,
              content_type: attachment.content_type,
              byte_size: attachment.byte_size
            }
          end
        }
      end

      def render_forbidden
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def render_invalid(error)
        render json: { error: "support_validation_failed", message: error.message }, status: :unprocessable_entity
      end

      def render_not_found
        render json: { error: "support_ticket_not_found" }, status: :not_found
      end
    end
  end
end
