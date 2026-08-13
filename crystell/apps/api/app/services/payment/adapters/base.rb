module Payment
  module Adapters
    class Error < StandardError; end
    class InvalidSignatureError < Error; end
    class InvalidPayloadError < Error; end

    class Base
      IntentResult = Data.define(:provider_intent_id, :status, :checkout_url, :provider_status, :metadata)
      WebhookResult = Data.define(:provider_event_id, :event_type, :provider_intent_id, :status, :amount_cents, :currency, :provider_transaction_id, :metadata)

      def initialize(account:)
        @account = account
      end

      def create_intent(payment_intent:)
        raise NotImplementedError
      end

      def verify_webhook!(raw_body:, headers:)
        raise NotImplementedError
      end

      def parse_webhook(raw_body:)
        raise NotImplementedError
      end

      private

      attr_reader :account
    end
  end
end
