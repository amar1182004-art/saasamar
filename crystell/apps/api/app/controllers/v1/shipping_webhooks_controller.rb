module V1
  class ShippingWebhooksController < ApplicationController
    def create
      result = Shipping::WebhookReceiver.call(
        endpoint_id: params.require(:endpoint_id),
        raw_body: request.raw_post,
        headers: request.headers
      )

      if result.event.status == "failed"
        render json: { error: "shipping_webhook_processing_failed" }, status: :unprocessable_entity
      else
        head :ok
      end
    rescue Shipping::WebhookEndpointResolver::UnknownEndpointError
      render json: { error: "shipping_webhook_not_found" }, status: :not_found
    rescue Shipping::WebhookEndpointResolver::DisabledEndpointError
      render json: { error: "shipping_webhook_disabled" }, status: :gone
    rescue Shipping::Adapters::InvalidSignatureError
      render json: { error: "shipping_webhook_signature_invalid" }, status: :unauthorized
    rescue Shipping::Adapters::InvalidPayloadError, ActionController::ParameterMissing
      render json: { error: "shipping_webhook_payload_invalid" }, status: :unprocessable_entity
    rescue Shipping::WebhookReceiver::ReplayConflictError
      render json: { error: "shipping_webhook_replay_conflict" }, status: :conflict
    end
  end
end
