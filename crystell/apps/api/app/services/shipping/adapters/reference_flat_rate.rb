require "digest"
require "json"
require "openssl"

module Shipping
  module Adapters
    class ReferenceFlatRate < Base
      SIGNATURE_HEADER = "X-Crystell-Shipping-Signature"

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

      def verify_webhook!(raw_body:, headers:)
        supplied = headers[SIGNATURE_HEADER] || headers[SIGNATURE_HEADER.downcase]
        secret = account.webhook_secret
        raise Shipping::Adapters::InvalidSignatureError, "shipping webhook secret is not configured" if secret.blank?
        raise Shipping::Adapters::InvalidSignatureError, "shipping webhook signature is missing" if supplied.blank?

        expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)
        valid = supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
        raise Shipping::Adapters::InvalidSignatureError, "shipping webhook signature is invalid" unless valid

        supplied
      end

      def parse_webhook(raw_body:)
        payload = JSON.parse(raw_body)
        occurred_at = payload["occurred_at"].present? ? Time.zone.parse(payload.fetch("occurred_at").to_s) : Time.current
        raise ArgumentError, "occurred_at is invalid" unless occurred_at

        WebhookResult.new(
          provider_event_id: payload.fetch("event_id").to_s,
          event_type: payload.fetch("event_type").to_s,
          provider_shipment_id: payload.fetch("shipment_id").to_s,
          status: payload.fetch("status").to_s,
          tracking_number: payload["tracking_number"]&.to_s,
          tracking_url: payload["tracking_url"]&.to_s,
          occurred_at: occurred_at,
          message: payload["message"]&.to_s,
          metadata: payload.fetch("metadata", {})
        )
      rescue JSON::ParserError, KeyError, ArgumentError, TypeError => error
        raise Shipping::Adapters::InvalidPayloadError, error.message
      end
    end
  end
end
