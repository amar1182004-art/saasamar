module Payment
  class IntentCreator
    class MissingTenantContextError < StandardError; end
    class InvalidOrderError < StandardError; end
    class IdempotencyConflictError < StandardError; end

    def self.call(order_id:, payment_provider_account_id:, idempotency_key:)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      raise InvalidOrderError, "idempotency key is required" if idempotency_key.blank?

      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        order = Order.lock.find(order_id)
        account = PaymentProviderAccount.active.find_by!(
          id: payment_provider_account_id,
          store_id: order.store_id
        )

        existing = PaymentIntent.find_by(
          tenant_id: Current.tenant_id,
          store_id: order.store_id,
          idempotency_key: idempotency_key
        )
        if existing
          result = verify_existing!(existing, order, account)
          next
        end

        raise InvalidOrderError, "order is already paid" if order.payment_status == "paid"
        raise InvalidOrderError, "order is cancelled" if order.status == "cancelled"
        raise InvalidOrderError, "checkout is not awaiting payment" unless order.checkout_session.status == "payment_pending"

        result = PaymentIntent.create!(
          tenant_id: Current.tenant_id,
          store_id: order.store_id,
          order_id: order.id,
          checkout_session_id: order.checkout_session_id,
          payment_provider_account_id: account.id,
          status: "created",
          currency: order.currency,
          amount_cents: order.total_cents,
          idempotency_key: idempotency_key,
          metadata: {}
        )
        order.update!(payment_status: "pending") unless order.payment_status == "pending"
      end

      result
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/payment_intents.*idempotency|idx_payment_intents_idempotency/i)

      order = Order.find(order_id)
      account = PaymentProviderAccount.find(payment_provider_account_id)
      existing = PaymentIntent.find_by!(
        tenant_id: Current.tenant_id,
        store_id: order.store_id,
        idempotency_key: idempotency_key
      )
      verify_existing!(existing, order, account)
    end

    def self.verify_existing!(intent, order, account)
      same_request = intent.order_id.to_s == order.id.to_s &&
        intent.payment_provider_account_id.to_s == account.id.to_s &&
        intent.amount_cents == order.total_cents &&
        intent.currency == order.currency
      return intent if same_request

      raise IdempotencyConflictError, "idempotency key was already used for another payment request"
    end
    private_class_method :verify_existing!
  end
end
