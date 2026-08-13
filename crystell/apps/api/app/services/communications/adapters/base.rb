module Communications
  module Adapters
    class Base
      Result = Data.define(:provider_message_id, :status, :metadata)

      def initialize(account:)
        @account = account
      end

      def deliver(channel:, recipient:, subject:, body:, idempotency_key:)
        raise NotImplementedError
      end

      private

      attr_reader :account
    end
  end
end
