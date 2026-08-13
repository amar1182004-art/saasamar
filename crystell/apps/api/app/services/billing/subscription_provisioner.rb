module Billing
  class SubscriptionProvisioner
    class MissingTenantContextError < StandardError; end
    class InvalidPriceError < StandardError; end
    class ExistingSubscriptionError < StandardError; end

    Result = Data.define(:subscription_id, :status, :period_start, :period_end, :trial_ends_at)

    def self.call(price_id:, started_at: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      TenantPermission.require!(Current.membership, "billing.manage")

      price = BillingPrice.includes(:billing_plan).find_by(id: price_id, status: "active")
      raise InvalidPriceError, "billing price is not active" unless price&.billing_plan&.status == "active"

      period_start = started_at
      period_end = price.interval == "annual" ? started_at + 1.year : started_at + 1.month
      trial_ends_at = price.billing_plan.trial_days.positive? ? started_at + price.billing_plan.trial_days.days : nil
      status = trial_ends_at ? "trialing" : "active"

      subscription = Subscription.transaction do
        raise ExistingSubscriptionError, "tenant already has a current subscription" if Subscription.current.exists?

        created = Subscription.create!(
          tenant_id: Current.tenant_id,
          billing_plan: price.billing_plan,
          billing_price: price,
          status: status,
          currency: price.currency,
          interval: price.interval,
          amount_cents: price.amount_cents,
          started_at: started_at,
          trial_ends_at: trial_ends_at,
          current_period_start: period_start,
          current_period_end: period_end,
          provider: price.provider
        )

        BillingEvent.create!(
          tenant_id: Current.tenant_id,
          event_type: "subscription.created",
          actor_user_id: Current.user&.id,
          subject_id: created.id,
          subject_type: "Subscription",
          metadata: {
            plan_code: price.billing_plan.code,
            price_id: price.id,
            interval: price.interval,
            amount_cents: price.amount_cents,
            currency: price.currency
          }
        )

        created
      end

      Result.new(
        subscription_id: subscription.id,
        status: subscription.status,
        period_start: subscription.current_period_start,
        period_end: subscription.current_period_end,
        trial_ends_at: subscription.trial_ends_at
      )
    rescue ActiveRecord::RecordNotUnique => error
      raise ExistingSubscriptionError, "tenant already has a current subscription" if error.message.include?("idx_subscriptions_one_current_per_tenant")

      raise
    end
  end
end
