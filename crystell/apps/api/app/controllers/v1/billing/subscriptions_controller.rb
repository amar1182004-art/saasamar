module V1
  module Billing
    class SubscriptionsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def show
        TenantPermission.require!(Current.membership, "billing.read")
        subscription = Subscription.current.includes(:billing_plan, :billing_price).order(current_period_end: :desc).first

        return render json: { subscription: nil } unless subscription

        render json: { subscription: serialize(subscription) }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def create
        TenantPermission.require!(Current.membership, "billing.manage")
        result = ::Billing::SubscriptionProvisioner.call(price_id: params.require(:price_id))
        subscription = Subscription.includes(:billing_plan, :billing_price).find(result.subscription_id)

        render json: { subscription: serialize(subscription) }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Billing::SubscriptionProvisioner::InvalidPriceError => error
        render json: { error: "invalid_billing_price", message: error.message }, status: :unprocessable_entity
      rescue ::Billing::SubscriptionProvisioner::ExistingSubscriptionError => error
        render json: { error: "subscription_exists", message: error.message }, status: :conflict
      end

      private

      def serialize(subscription)
        {
          id: subscription.id,
          status: subscription.status,
          plan: {
            id: subscription.billing_plan.id,
            code: subscription.billing_plan.code,
            name: subscription.billing_plan.name
          },
          price: {
            id: subscription.billing_price.id,
            currency: subscription.currency,
            interval: subscription.interval,
            amount_cents: subscription.amount_cents
          },
          started_at: subscription.started_at,
          trial_ends_at: subscription.trial_ends_at,
          current_period_start: subscription.current_period_start,
          current_period_end: subscription.current_period_end,
          cancel_at_period_end: subscription.cancel_at_period_end
        }
      end
    end
  end
end
