require "digest"

module Shipping
  module Adapters
    class ReferenceFlatRate < Base
      def quote(checkout_session:, destination:, parcels:)
        credentials = account.credentials
        base_cents = Integer(credentials.fetch("base_rate_cents", 5000))
        per_item_cents = Integer(credentials.fetch("per_item_cents", 500))
        quantity = parcels.sum { |parcel| Integer(parcel.fetch(:quantity, 1)) }
        amount_cents = base_cents + (per_item_cents * quantity)
        now = Time.current

        [
          Rate.new(
            provider_quote_id: "refq_#{Digest::SHA256.hexdigest("#{checkout_session.id}:#{amount_cents}")[0, 20]}",
            service_code: "standard",
            service_name: "Reference Standard",
            amount_cents: amount_cents,
            currency: checkout_session.currency,
            expires_at: now + 15.minutes,
            metadata: { "destination_country" => destination["country_code"] }
          )
        ]
      end

      def create_shipment(shipment:)
        suffix = Digest::SHA256.hexdigest(shipment.id.to_s)[0, 16].upcase
        ShipmentResult.new(
          provider_shipment_id: "refs_#{shipment.id}",
          status: "label_ready",
          tracking_number: "CRYSTELL#{suffix}",
          tracking_url: "https://example.invalid/track/CRYSTELL#{suffix}",
          label_url: "https://example.invalid/labels/#{shipment.id}.pdf",
          metadata: { "reference_adapter" => true }
        )
      end

      def cancel_shipment(shipment:)
        ShipmentResult.new(
          provider_shipment_id: shipment.provider_shipment_id,
          status: "cancelled",
          tracking_number: shipment.tracking_number,
          tracking_url: shipment.tracking_url,
          label_url: shipment.label_url,
          metadata: shipment.metadata.merge("cancelled_by_reference_adapter" => true)
        )
      end
    end
  end
end
