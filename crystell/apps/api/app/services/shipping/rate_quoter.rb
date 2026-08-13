require "digest"
require "json"

module Shipping
  class RateQuoter
    class MissingTenantContextError < StandardError; end
    class InvalidCheckoutError < StandardError; end
    class InvalidDestinationError < StandardError; end

    def self.call(checkout_session_id:, shipping_provider_account_id:, destination:)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      checkout = CheckoutSession.find(checkout_session_id)
      raise InvalidCheckoutError, "checkout is not available for shipping quotes" unless %w[open inventory_reserved].include?(checkout.status)
      raise InvalidCheckoutError, "checkout has expired" if checkout.expires_at <= Time.current

      normalized_destination = normalize_destination(destination)
      account = ShippingProviderAccount.active.find(shipping_provider_account_id)
      raise ActiveRecord::RecordNotFound, "shipping provider scope mismatch" unless account.store_id == checkout.store_id

      parcels = CheckoutLineItem.where(checkout_session_id: checkout.id).order(:id).map do |line|
        {
          product_variant_id: line.product_variant_id,
          quantity: line.quantity,
          metadata: line.metadata
        }
      end
      raise InvalidCheckoutError, "checkout must contain at least one line" if parcels.empty?

      request_digest = Digest::SHA256.hexdigest(JSON.generate({
        checkout_id: checkout.id,
        account_id: account.id,
        destination: normalized_destination,
        parcels: parcels
      }))

      adapter = AdapterRegistry.build(account)
      adapter.quote(
        checkout_session: checkout,
        destination: normalized_destination,
        parcels: parcels
      ).map do |rate|
        ShippingRateQuote.find_or_create_by!(
          tenant_id: Current.tenant_id,
          store_id: checkout.store_id,
          checkout_session_id: checkout.id,
          shipping_provider_account_id: account.id,
          request_digest: request_digest,
          service_code: rate.service_code
        ) do |quote|
          quote.provider_quote_id = rate.provider_quote_id
          quote.service_name = rate.service_name
          quote.currency = rate.currency
          quote.amount_cents = rate.amount_cents
          quote.expires_at = rate.expires_at
          quote.metadata = rate.metadata || {}
        end
      end
    end

    def self.normalize_destination(value)
      input = value.respond_to?(:to_h) ? value.to_h.stringify_keys : {}
      country_code = input["country_code"].to_s.strip.upcase
      raise InvalidDestinationError, "country_code must be ISO alpha-2" unless country_code.match?(/\A[A-Z]{2}\z/)

      {
        "country_code" => country_code,
        "postal_code" => input["postal_code"].to_s.strip.presence,
        "city" => input["city"].to_s.strip.presence,
        "state" => input["state"].to_s.strip.presence
      }.compact
    end
    private_class_method :normalize_destination
  end
end
