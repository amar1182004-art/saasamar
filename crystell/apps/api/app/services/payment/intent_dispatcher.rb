module Payment
  class IntentDispatcher
    class MissingTenantContextError < StandardError; end
    class InvalidIntentError < StandardError; end

    def self.call(payment_intent_id:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      intent = PaymentIntent.includes(:payment_provider_account).find(payment_intent_id)
      return intent if %w[requires_action authorized paid cancelled].include?(intent.status)
      raise InvalidIntentError, "payment intent cannot be dispatched" unless %w[created pending failed].include?(intent.status)

      account = intent.payment_provider_account
      adapter = Payment::AdapterRegistry.build(account)
      provider_result = adapter.create_intent(payment_intent: intent)

      ApplicationRecord.transaction(requires_new: true) do
        locked = PaymentIntent.lock.find(intent.id)
        if locked.provider_intent_id.present?
          unless locked.provider_intent_id == provider_result.provider_intent_id
            raise InvalidIntentError, "provider returned a conflicting payment intent reference"
          end
          return locked
        end

        locked.update!(
          provider_intent_id: provider_result.provider_intent_id,
          provider_status: provider_result.provider_status,
          status: normalize_status(provider_result.status),
          checkout_url: provider_result.checkout_url,
          dispatched_at: now,
          last_error_code: nil,
          last_error_message: nil,
          metadata: locked.metadata.merge(provider_result.metadata || {})
        )
        locked
      end
    rescue Payment::AdapterRegistry::UnsupportedProviderError,
           Payment::AdapterRegistry::DisabledProviderError => error
      mark_failed!(payment_intent_id, error, now)
      raise InvalidIntentError, error.message
    end

    def self.normalize_status(value)
      status = value.to_s
      return status if %w[pending requires_action authorized paid].include?(status)

      raise InvalidIntentError, "adapter returned an invalid payment intent status"
    end
    private_class_method :normalize_status

    def self.mark_failed!(payment_intent_id, error, now)
      PaymentIntent.where(id: payment_intent_id).update_all(
        status: "failed",
        last_error_code: error.class.name,
        last_error_message: error.message.to_s.first(1_000),
        failed_at: now,
        updated_at: now
      )
    end
    private_class_method :mark_failed!
  end
end
