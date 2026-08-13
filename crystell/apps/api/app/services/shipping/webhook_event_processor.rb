module Shipping
  class WebhookEventProcessor
    class MissingTenantContextError < StandardError; end

    ALLOWED_TRANSITIONS = {
      "pending" => %w[submitted label_ready in_transit delivered failed cancelled],
      "submitted" => %w[label_ready in_transit delivered failed cancelled],
      "label_ready" => %w[in_transit delivered failed cancelled],
      "in_transit" => %w[delivered failed],
      "failed" => [],
      "delivered" => [],
      "cancelled" => []
    }.freeze

    def self.call(event:, parsed:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      ApplicationRecord.transaction(requires_new: true) do
        locked_event = ShippingWebhookEvent.lock.find(event.id)
        return locked_event if %w[processed ignored].include?(locked_event.status)

        shipment = Shipment.lock.find_by(
          shipping_provider_account_id: locked_event.shipping_provider_account_id,
          provider_shipment_id: parsed.provider_shipment_id
        )
        unless shipment
          locked_event.update!(status: "ignored", processed_at: now, failure_reason: "shipment_not_found")
          return locked_event
        end

        incoming_status = parsed.status.to_s
        unless Shipment.validators_on(:status).any? { |validator| validator.options[:in]&.include?(incoming_status) }
          locked_event.update!(shipment_id: shipment.id, status: "ignored", processed_at: now, failure_reason: "unsupported_status")
          return locked_event
        end

        current_status = shipment.status
        unless incoming_status == current_status || ALLOWED_TRANSITIONS.fetch(current_status, []).include?(incoming_status)
          locked_event.update!(shipment_id: shipment.id, status: "ignored", processed_at: now, failure_reason: "invalid_status_transition")
          return locked_event
        end

        shipment.update!(
          status: incoming_status,
          tracking_number: parsed.tracking_number.presence || shipment.tracking_number,
          tracking_url: parsed.tracking_url.presence || shipment.tracking_url,
          metadata: shipment.metadata.merge(parsed.metadata.to_h)
        )

        ShipmentEvent.create!(
          tenant_id: Current.tenant_id,
          store_id: shipment.store_id,
          shipment_id: shipment.id,
          event_type: parsed.event_type,
          status: incoming_status,
          occurred_at: parsed.occurred_at || now,
          message: parsed.message.presence,
          metadata: parsed.metadata.to_h.merge("provider_event_id" => locked_event.provider_event_id)
        )

        locked_event.update!(
          shipment_id: shipment.id,
          status: "processed",
          processed_at: now,
          failure_reason: nil
        )
        locked_event
      end
    rescue StandardError => error
      mark_failed!(event.id, error, now)
      raise
    end

    def self.mark_failed!(event_id, error, now)
      ShippingWebhookEvent.where(id: event_id).update_all(
        status: "failed",
        failure_reason: "#{error.class}: #{error.message}".first(1_000),
        processed_at: now,
        updated_at: now
      )
    rescue StandardError
      nil
    end
    private_class_method :mark_failed!
  end
end
