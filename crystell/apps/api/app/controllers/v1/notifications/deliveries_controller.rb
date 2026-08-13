module V1
  module Notifications
    class DeliveriesController < ApplicationController
      include Authentication
      include TenantAuthorization

      def create
        delivery = ::Notifications::DeliveryQueue.call(
          store_id: params.require(:store_id),
          template_key: params.require(:template_key),
          channel: params.require(:channel),
          locale: params.fetch(:locale, "ar"),
          recipient: params.require(:recipient),
          variables: variables,
          idempotency_key: params.require(:idempotency_key),
          user_id: params[:user_id],
          provider_key: params[:provider_key]
        )
        render json: {
          notification_delivery: {
            id: delivery.id,
            channel: delivery.channel,
            status: delivery.status,
            scheduled_at: delivery.scheduled_at
          }
        }, status: :accepted
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Notifications::DeliveryQueue::IdempotencyConflictError => error
        render json: { error: "notification_idempotency_conflict", message: error.message }, status: :conflict
      rescue ::Notifications::DeliveryQueue::InvalidDeliveryError,
             ::Notifications::TemplateRenderer::InvalidTemplateError,
             ActionController::ParameterMissing => error
        render json: { error: "notification_delivery_invalid", message: error.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "notification_delivery_configuration_missing" }, status: :unprocessable_entity
      end

      private

      def variables
        value = params[:variables]
        return {} if value.blank?

        value.permit!.to_h
      end
    end
  end
end
