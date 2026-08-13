module V1
  module Support
    class MessagesController < ApplicationController
      include Authentication
      include TenantAuthorization

      def create
        message = ::Support::TicketDesk.reply(
          store_id: params.require(:store_id),
          ticket_id: params.require(:ticket_id),
          body: params.require(:body),
          attachment_ids: params[:attachment_ids]
        )
        render json: {
          support_message: {
            id: message.id,
            author_type: message.author_type,
            body: message.body,
            created_at: message.created_at
          }
        }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Support::TicketDesk::ClosedTicketError => error
        render json: { error: "support_ticket_closed", message: error.message }, status: :conflict
      rescue ::Support::TicketDesk::InvalidTicketError, ActionController::ParameterMissing => error
        render json: { error: "support_validation_failed", message: error.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "support_ticket_not_found" }, status: :not_found
      end
    end
  end
end
