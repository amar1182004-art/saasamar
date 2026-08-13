module V1
  module Billing
    class PlansController < ApplicationController
      def index
        plans = BillingPlan
          .where(status: "active", public: true)
          .includes(:billing_prices, billing_entitlements: :billing_feature)
          .order(:position, :created_at)

        render json: {
          plans: plans.map do |plan|
            {
              id: plan.id,
              code: plan.code,
              name: plan.name,
              trial_days: plan.trial_days,
              prices: plan.billing_prices.select { |price| price.status == "active" }.map do |price|
                {
                  id: price.id,
                  currency: price.currency,
                  interval: price.interval,
                  amount_cents: price.amount_cents
                }
              end,
              entitlements: plan.billing_entitlements.each_with_object({}) do |entitlement, result|
                result[entitlement.billing_feature.key] = entitlement.value
              end
            }
          end
        }
      end
    end
  end
end
