module Billing
  class SubscriptionLifecycle
    class MissingTenantContextError < StandardError; end
    class MissingSubscriptionError < StandardError; end
    class InvalidStateError < StandardError; end

    Result = Data.define(:subscription_id, :status, :cancel_at_period_end, :current_period_end)

    def self.schedule_cancellation
      mutate!(event_type: "subscription.cancellation_scheduled") do |subscription|
        raise InvalidStateError, "subscription cannot be canceled from its current state" unless subscription.status.in?(%w[trialing active past_due paused])

        subscription.cancel_at_period_end = true
      end
    end

    def self.resume
      mutate!(event_type: "subscription.cancellation_reverted") do |subscription|
        raise InvalidStateError, "subscription does not have a scheduled cancellation" unless subscription.cancel_at_period_end?
        raise InvalidStateError, "subscription cannot be resumed from its current state" unless subscription.status.in?(%w[trialing active past_due paused])

        subscription.cancel_at_period_end = false
        subscription.canceled_at = nil
      end
    end

    def self.mutate!(event_type:)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      TenantPermission.require!(Current.membership, "billing.manage")

      subscription = Subscription.current.order(current_period_end: :desc).first
      raise MissingSubscriptionError, "tenant does not have a current subscription" unless subscription

      Subscription.transaction do
        subscription.lock!
        yield subscription
        subscription.save!

        BillingEvent.create!(
          tenant_id: Current.tenant_id,
          event_type: event_type,
          actor_user_id: Current.user&.id,
          subject_id: subscription.id,
          subject_type: "Subscription",
          metadata: {
            status: subscription.status,
            cancel_at_period_end: subscription.cancel_at_period_end,
            current_period_end: subscription.current_period_end
          }
        )
      end

      Result.new(
        subscription_id: subscription.id,
        status: subscription.status,
        cancel_at_period_end: subscription.cancel_at_period_end,
        current_period_end: subscription.current_period_end
      )
    end
    private_class_method :mutate!
  end
end
