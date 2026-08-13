module Shipping
  class QuoteSelector
    class MissingTenantContextError < StandardError; end
    class InvalidQuoteError < StandardError; end

    def self.call(checkout_session_id:, shipping_rate_quote_id:, shipping_address:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      TenantPermission.require!(Current.membership, "shipping.manage")

      ApplicationRecord.transaction(requires_new: true) do
        checkout = CheckoutSession.lock.find(checkout_session_id)
        raise InvalidQuoteError, "checkout cannot change shipping in its current state" unless %w[open inventory_reserved].include?(checkout.status)
        raise InvalidQuoteError, "checkout has expired" if checkout.expires_at <= now

        quote = ShippingRateQuote.find(shipping_rate_quote_id)
        raise InvalidQuoteError, "shipping quote belongs to another checkout" unless quote.checkout_session_id == checkout.id
        raise InvalidQuoteError, "shipping quote has expired" if quote.expires_at <= now
        raise InvalidQuoteError, "shipping quote currency mismatch" unless quote.currency == checkout.currency

        address = shipping_address.respond_to?(:to_h) ? shipping_address.to_h.stringify_keys : {}
        country_code = address["country_code"].to_s.strip.upcase
        raise InvalidQuoteError, "shipping address country_code is required" unless country_code.match?(/\A[A-Z]{2}\z/)
        address["country_code"] = country_code

        new_total = checkout.subtotal_cents - checkout.discount_cents + quote.amount_cents + checkout.tax_cents
        checkout.update!(
          selected_shipping_rate_quote_id: quote.id,
          shipping_cents: quote.amount_cents,
          total_cents: new_total,
          shipping_address: address
        )

        checkout
      end
    end
  end
end
