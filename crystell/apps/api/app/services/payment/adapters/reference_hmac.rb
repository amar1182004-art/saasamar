require "openssl"
require "json"
require "digest"

module Payment
  module Adapters
    class ReferenceHmac < Base
      SIGNATURE_HEADER = "X-Crystell-Signature"

      def create_intent(payment_intent:)
        credentials = account.credentials
        checkout_base_url = credentials.fetch("checkout_base_url", "https://payments.invalid/checkout")
        provider_intent_id = "ref_#{Digest::SHA256.hexdigest(payment_intent.idempotency_key)[0, 24]}"

        IntentResult.new(
          provider_intent_id: provider_intent_id,
          status: "requires_action",
          checkout_url: "#{checkout_base_url}/#{provider_intent_id}",
          provider_status: "requires_action",
          metadata: { "adapter" => "reference_hmac" }
        )
      end

      def verify_webhook!(raw_body:, headers:)
        supplied = headers[SIGNATURE_HEADER] || headers[SIGNATURE_HEADER.downcase]
        raise Payment::Adapters::InvalidSignatureError, "payment webhook signature is missing" if supplied.blank?

        expected = OpenSSL::HMAC.hexdigest("SHA256", account.webhook_secret, raw_body)
        valid = supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
        raise Payment::Adapters::InvalidSignatureError, "payment webhook signature is invalid" unless valid

        supplied
      end

      def parse_webhook(raw_body:)
        payload = JSON.parse(raw_body)
        WebhookResult.new(
          provider_event_id: payload.fetch("event_id").to_s,
          event_type: payload.fetch("event_type").to_s,
          provider_intent_id: payload.fetch("payment_intent_id").to_s,
          status: payload.fetch("status").to_s,
          amount_cents: Integer(payload.fetch("amount_cents")),
          currency: payload.fetch("currency").to_s.upcase,
          provider_transaction_id: payload["transaction_id"]&.to_s,
          metadata: payload.fetch("metadata", {})
        )
      rescue JSON::ParserError, KeyError, ArgumentError, TypeError => error
        raise Payment::Adapters::InvalidPayloadError, error.message
      end
    end
  end
end
