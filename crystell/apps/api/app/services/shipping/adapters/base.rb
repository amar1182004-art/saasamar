module Shipping
  module Adapters
    class Base
      Rate = Data.define(:provider_quote_id, :service_code, :service_name, :amount_cents, :currency, :expires_at, :metadata)
      ShipmentResult = Data.define(:provider_shipment_id, :status, :tracking_number, :tracking_url, :label_url, :metadata)

      def initialize(account:)
        @account = account
      end

      def quote(checkout_session:, destination:, parcels:)
        raise NotImplementedError
      end

      def create_shipment(shipment:)
        raise NotImplementedError
      end

      def cancel_shipment(shipment:)
        raise NotImplementedError
      end

      private

      attr_reader :account
    end
  end
end
