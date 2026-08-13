module Billing
  class InvoiceIssuer
    class MissingTenantContextError < StandardError; end
    class InvalidSubscriptionError < StandardError; end

    Result = Data.define(:invoice_id, :number, :subtotal_cents, :discount_cents, :total_cents, :currency)

    def self.call(subscription_id:, coupon_code: nil, issued_at: Time.current, due_at: nil)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      subscription = Subscription.find_by(id: subscription_id)
      raise InvalidSubscriptionError, "subscription is not billable" unless subscription&.status.in?(%w[trialing active past_due])

      subtotal_cents = subscription.amount_cents
      quote = coupon_code.present? ? CouponQuote.call(code: coupon_code, subscription: subscription, subtotal_cents: subtotal_cents, at: issued_at) : nil
      discount_cents = quote&.discount_cents.to_i
      total_cents = subtotal_cents - discount_cents
      invoice_number = next_number(issued_at)

      invoice = Invoice.transaction do
        created = Invoice.create!(
          tenant_id: Current.tenant_id,
          subscription: subscription,
          number: invoice_number,
          status: "open",
          currency: subscription.currency,
          subtotal_cents: subtotal_cents,
          discount_cents: discount_cents,
          tax_cents: 0,
          total_cents: total_cents,
          amount_paid_cents: 0,
          issued_at: issued_at,
          due_at: due_at || issued_at
        )

        if quote
          BillingCouponRedemption.create!(
            tenant_id: Current.tenant_id,
            billing_coupon_id: quote.coupon_id,
            subscription: subscription,
            invoice: created,
            idempotency_key: "invoice:#{created.id}:coupon",
            discount_cents: discount_cents,
            redeemed_at: issued_at
          )
        end

        BillingEvent.create!(
          tenant_id: Current.tenant_id,
          event_type: "invoice.issued",
          actor_user_id: Current.user&.id,
          subject_id: created.id,
          subject_type: "Invoice",
          metadata: {
            number: created.number,
            subscription_id: subscription.id,
            subtotal_cents: subtotal_cents,
            discount_cents: discount_cents,
            total_cents: total_cents,
            currency: subscription.currency,
            coupon_code: quote&.code
          }
        )

        created
      end

      Result.new(
        invoice_id: invoice.id,
        number: invoice.number,
        subtotal_cents: invoice.subtotal_cents,
        discount_cents: invoice.discount_cents,
        total_cents: invoice.total_cents,
        currency: invoice.currency
      )
    end

    def self.next_number(time)
      "CRY-#{time.utc.strftime('%Y%m%d')}-#{SecureRandom.hex(6).upcase}"
    end
    private_class_method :next_number
  end
end
