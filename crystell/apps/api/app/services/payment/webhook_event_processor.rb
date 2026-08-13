module Payment
  class WebhookEventProcessor
    class MissingTenantContextError < StandardError; end
    class InvalidEventError < StandardError; end

    def self.call(event:, parsed:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      ApplicationRecord.transaction(requires_new: true) do
        locked_event = PaymentWebhookEvent.lock.find(event.id)
        return locked_event if %w[processed ignored].include?(locked_event.status)

        intent = PaymentIntent.lock.find_by(
          payment_provider_account_id: locked_event.payment_provider_account_id,
          provider_intent_id: parsed.provider_intent_id
        )
        unless intent
          locked_event.update!(status: "ignored", processed_at: now, failure_reason: "payment_intent_not_found")
          return locked_event
        end

        validate_money!(intent, parsed)

        case parsed.event_type
        when "payment.authorized"
          process_authorized!(intent, locked_event, parsed, now)
        when "payment.succeeded"
          process_succeeded!(intent, locked_event, parsed, now)
        when "payment.failed"
          process_failed!(intent, locked_event, parsed, now)
        else
          locked_event.update!(status: "ignored", processed_at: now, failure_reason: "unsupported_event_type")
          return locked_event
        end

        locked_event.update!(status: "processed", processed_at: now, failure_reason: nil)
        locked_event
      end
    rescue StandardError => error
      mark_failed!(event.id, error, now)
      raise
    end

    def self.process_authorized!(intent, event, parsed, now)
      return if intent.status == "paid"

      record_transaction!(intent, event, parsed, kind: "authorization", status: "succeeded")
      intent.update!(
        status: "authorized",
        provider_status: parsed.status,
        authorized_at: now,
        last_error_code: nil,
        last_error_message: nil
      )
      intent.order.update!(payment_status: "authorized")
    end
    private_class_method :process_authorized!

    def self.process_succeeded!(intent, event, parsed, now)
      unless intent.status == "paid"
        record_transaction!(intent, event, parsed, kind: "capture", status: "succeeded")

        CheckoutInventoryReservation.where(checkout_session_id: intent.checkout_session_id)
                                    .order(:inventory_reservation_id)
                                    .pluck(:inventory_reservation_id)
                                    .each do |reservation_id|
          Inventory::ConsumedReservation.call(reservation_id: reservation_id, now: now)
        end

        intent.update!(
          status: "paid",
          provider_status: parsed.status,
          paid_at: now,
          last_error_code: nil,
          last_error_message: nil
        )
        order = intent.order
        order.update!(payment_status: "paid", status: "confirmed")
        checkout = intent.checkout_session
        checkout.update!(status: "completed", completed_at: now)
        checkout.cart.update!(status: "converted")
      end
    end
    private_class_method :process_succeeded!

    def self.process_failed!(intent, event, parsed, now)
      return if intent.status == "paid"

      record_transaction!(intent, event, parsed, kind: "failure", status: "failed")
      intent.update!(
        status: "failed",
        provider_status: parsed.status,
        failed_at: now,
        last_error_code: "provider_failure",
        last_error_message: parsed.metadata.to_h["message"].to_s.first(1_000).presence
      )
      intent.order.update!(payment_status: "failed")
    end
    private_class_method :process_failed!

    def self.record_transaction!(intent, event, parsed, kind:, status:)
      source_reference = parsed.provider_transaction_id.presence || event.provider_event_id
      key = "provider:#{source_reference}:#{kind}"
      existing = PaymentTransaction.find_by(
        tenant_id: Current.tenant_id,
        store_id: intent.store_id,
        payment_intent_id: intent.id,
        idempotency_key: key
      )
      return existing if existing

      PaymentTransaction.create!(
        tenant_id: Current.tenant_id,
        store_id: intent.store_id,
        payment_intent_id: intent.id,
        kind: kind,
        status: status,
        currency: intent.currency,
        amount_cents: parsed.amount_cents,
        idempotency_key: key,
        provider_transaction_id: parsed.provider_transaction_id,
        occurred_at: Time.current,
        metadata: { "provider_event_id" => event.provider_event_id }
      )
    end
    private_class_method :record_transaction!

    def self.validate_money!(intent, parsed)
      amount = Integer(parsed.amount_cents)
      currency = parsed.currency.to_s.upcase
      return if amount == intent.amount_cents && currency == intent.currency

      raise InvalidEventError, "payment webhook amount or currency does not match the payment intent"
    end
    private_class_method :validate_money!

    def self.mark_failed!(event_id, error, now)
      PaymentWebhookEvent.where(id: event_id).update_all(
        status: "failed",
        failure_reason: "#{error.class}: #{error.message}".first(1_000),
        processed_at: now,
        updated_at: now
      )
    rescue StandardError
      nil
    end
    private_class_method :mark_failed!
  end
end
