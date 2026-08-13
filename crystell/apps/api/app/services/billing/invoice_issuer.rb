module Billing
  class InvoiceIssuer
    class MissingTenantContextError < StandardError; end
    class InvalidSubscriptionError < StandardError; end

    Result = Data.define(:invoice_id, :number, :subtotal_cents, :discount_cents, :total_cents, :currency)

    def self.call(subscription_id:, coupon_code: nil, issued_at: Time.current, due_at: nil, idempotency_key: nil)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      subscription = Subscription.find_by(id: subscription_id)
      raise InvalidSubscriptionError, "subscription is not billable" unless subscription&.status.in?(%w[trialing active past_due])

      operation_key = idempotency_key.presence || default_idempotency_key(subscription)
      existing = Invoice.find_by(idempotency_key: operation_key)
      return result_for(existing) if existing

      invoice = Invoice.transaction do
        normalized_coupon_code = coupon_code.to_s.strip.upcase.presence
        lock_coupon!(normalized_coupon_code) if normalized_coupon_code

        existing_inside_transaction = Invoice.find_by(idempotency_key: operation_key)
        next existing_inside_transaction if existing_inside_transaction

        subtotal_cents = subscription.amount_cents
        quote = if normalized_coupon_code
          CouponQuote.call(
            code: normalized_coupon_code,
            subscription: subscription,
            subtotal_cents: subtotal_cents,
            at: issued_at
          )
        end
        discount_cents = quote&.discount_cents.to_i
        total_cents = subtotal_cents - discount_cents

        created = Invoice.create!(
          tenant_id: Current.tenant_id,
          subscription: subscription,
          number: next_number(issued_at),
          idempotency_key: operation_key,
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
            coupon_code: quote&.code,
            idempotency_key: operation_key
          }
        )

        created
      end

      result_for(invoice)
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/idx_invoices_tenant_idempotency|idempotency_key/i)

      result_for(Invoice.find_by!(tenant_id: Current.tenant_id, idempotency_key: operation_key))
    end

    def self.lock_coupon!(code)
      connection = ApplicationRecord.connection
      connection.execute(
        "SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote(code)}, 0))"
      )
    end
    private_class_method :lock_coupon!

    def self.default_idempotency_key(subscription)
      "subscription:#{subscription.id}:period:#{subscription.current_period_start.to_i}"
    end
    private_class_method :default_idempotency_key

    def self.next_number(time)
      "CRY-#{time.utc.strftime('%Y%m%d')}-#{SecureRandom.hex(6).upcase}"
    end
    private_class_method :next_number

    def self.result_for(invoice)
      Result.new(
        invoice_id: invoice.id,
        number: invoice.number,
        subtotal_cents: invoice.subtotal_cents,
        discount_cents: invoice.discount_cents,
        total_cents: invoice.total_cents,
        currency: invoice.currency
      )
    end
    private_class_method :result_for
  end
end
