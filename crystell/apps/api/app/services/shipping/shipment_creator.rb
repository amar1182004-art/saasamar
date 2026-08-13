module Shipping
  class ShipmentCreator
    class MissingTenantContextError < StandardError; end
    class InvalidOrderError < StandardError; end
    class InvalidQuoteError < StandardError; end

    def self.call(order_id:, idempotency_key:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      TenantPermission.require!(Current.membership, "shipping.manage")
      raise InvalidOrderError, "idempotency key is required" if idempotency_key.blank?

      shipment = nil
      ApplicationRecord.transaction(requires_new: true) do
        order = Order.lock.find(order_id)
        checkout = order.checkout_session
        quote = checkout.selected_shipping_rate_quote

        raise InvalidQuoteError, "order has no selected shipping quote" unless quote
        raise InvalidQuoteError, "selected shipping quote has expired" if quote.expires_at <= now
        raise InvalidQuoteError, "shipping quote amount mismatch" unless quote.amount_cents == order.shipping_cents
        raise InvalidQuoteError, "shipping quote currency mismatch" unless quote.currency == order.currency

        existing = Shipment.find_by(idempotency_key: idempotency_key)
        if existing
          raise InvalidOrderError, "idempotency key belongs to another order" unless existing.order_id == order.id
          shipment = existing
          next
        end

        account = quote.shipping_provider_account
        shipment = Shipment.create!(
          tenant_id: Current.tenant_id,
          store_id: order.store_id,
          order_id: order.id,
          shipping_provider_account_id: account.id,
          status: "pending",
          service_code: quote.service_code,
          currency: order.currency,
          shipping_cost_cents: quote.amount_cents,
          idempotency_key: idempotency_key,
          destination_snapshot: order.shipping_address,
          metadata: { "shipping_rate_quote_id" => quote.id }
        )

        result = AdapterRegistry.build(account).create_shipment(shipment: shipment)
        shipment.update!(
          provider_shipment_id: result.provider_shipment_id,
          status: result.status,
          tracking_number: result.tracking_number,
          tracking_url: result.tracking_url,
          label_url: result.label_url,
          metadata: shipment.metadata.merge(result.metadata || {}),
          submitted_at: now
        )

        ShipmentEvent.create!(
          tenant_id: Current.tenant_id,
          store_id: order.store_id,
          shipment_id: shipment.id,
          event_type: "shipment_created",
          status: shipment.status,
          occurred_at: now,
          metadata: { "provider_shipment_id" => shipment.provider_shipment_id }
        )
      end

      shipment
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/idx_shipments_idempotency/i)

      Shipment.find_by!(idempotency_key: idempotency_key)
    end
  end
end
