module V1
  class PaymentWebhooksController < ApplicationController
    def create
      result = Payment::WebhookReceiver.call(
        endpoint_id: params.require(:endpoint_id),
        raw_body: request.raw_post,
        headers: request.headers
      )

      if result.event.status == "failed"
        render json: { error: "payment_webhook_processing_failed" }, status: :unprocessable_entity
      else
        head :ok
      end
    rescue Payment::WebhookEndpointResolver::UnknownEndpointError
      render json: { error: "payment_webhook_not_found" }, status: :not_found
    rescue Payment::WebhookEndpointResolver::DisabledEndpointError
      render json: { error: "payment_webhook_disabled" }, status: :gone
    rescue Payment::Adapters::ReferenceHmac::InvalidSignatureError
      render json: { error: "payment_webhook_signature_invalid" }, status: :unauthorized
    rescue Payment::Adapters::ReferenceHmac::InvalidPayloadError, ActionController::ParameterMissing
      render json: { error: "payment_webhook_payload_invalid" }, status: :unprocessable_entity
    rescue Payment::WebhookReceiver::ReplayConflictError
      render json: { error: "payment_webhook_replay_conflict" }, status: :conflict
    end
  end
end
