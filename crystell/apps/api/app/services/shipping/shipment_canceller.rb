module Shipping
  class ShipmentCanceller
    class MissingTenantContextError < StandardError; end
    class InvalidShipmentError < StandardError; end
    class CancellationNotAllowedError < StandardError; end

    CANCELLABLE_STATUSES = %w[pending submitted label_ready].freeze

    def self.call(store_id:, shipment_id:, reason: nil, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      TenantPermission.require!(Current.membership, "shipping.manage")

      shipment = nil
      ApplicationRecord.transaction(requires_new: true) do
        shipment = Shipment.lock.find_by(id: shipment_id, store_id: store_id)
        raise InvalidShipmentError, "shipment was not found" unless shipment
        next if shipment.status == "cancelled"

        unless CANCELLABLE_STATUSES.include?(shipment.status)
          raise CancellationNotAllowedError, "shipment cannot be cancelled from #{shipment.status}"
        end

        account = shipment.shipping_provider_account
        result = AdapterRegistry.build(account).cancel_shipment(shipment: shipment)
        raise CancellationNotAllowedError, "provider did not cancel shipment" unless result.status == "cancelled"

        metadata = shipment.metadata.merge(result.metadata || {})
        metadata["cancellation_reason"] = reason.to_s if reason.present?

        shipment.update!(
          status: "cancelled",
          tracking_number: result.tracking_number || shipment.tracking_number,
          tracking_url: result.tracking_url || shipment.tracking_url,
          label_url: result.label_url || shipment.label_url,
          metadata: metadata,
          cancelled_at: shipment.cancelled_at || now
        )

        ShipmentEvent.create!(
          tenant_id: Current.tenant_id,
          store_id: shipment.store_id,
          shipment_id: shipment.id,
          event_type: "shipment_cancelled",
          status: "cancelled",
          occurred_at: now,
          message: reason.to_s.presence,
          metadata: { "provider_shipment_id" => shipment.provider_shipment_id }.compact
        )
      end

      shipment
    end
  end
end
