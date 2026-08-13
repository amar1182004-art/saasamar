module Shipping
  class WebhookEndpointResolver
    class UnknownEndpointError < StandardError; end
    class DisabledEndpointError < StandardError; end

    Result = Data.define(:tenant_id, :store_id, :shipping_provider_account_id, :provider_key)

    def self.call(endpoint_id:)
      endpoint_uuid = endpoint_id.to_s
      raise UnknownEndpointError, "shipping webhook endpoint is invalid" unless endpoint_uuid.match?(/\A[0-9a-f-]{36}\z/i)

      connection = ApplicationRecord.connection
      row = connection.select_one(<<~SQL)
        SELECT *
        FROM crystell.resolve_shipping_webhook_endpoint(#{connection.quote(endpoint_uuid)}::uuid)
      SQL
      raise UnknownEndpointError, "shipping webhook endpoint was not found" unless row
      raise DisabledEndpointError, "shipping webhook endpoint is disabled" unless row.fetch("account_status") == "active"

      Result.new(
        tenant_id: row.fetch("tenant_id"),
        store_id: row.fetch("store_id"),
        shipping_provider_account_id: row.fetch("shipping_provider_account_id"),
        provider_key: row.fetch("provider_key")
      )
    rescue ActiveRecord::StatementInvalid => error
      raise UnknownEndpointError, error.message if error.message.match?(/invalid input syntax for type uuid/i)

      raise
    end
  end
end
