module V1
  module Billing
    class EntitlementsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        TenantPermission.require!(Current.membership, "billing.read")
        subscription = Subscription.current.includes(:billing_plan).order(current_period_end: :desc).first
        return render json: { plan: nil, entitlements: {} } unless subscription

        values = BillingEntitlement.where(billing_plan_id: subscription.billing_plan_id).includes(:billing_feature).each_with_object({}) do |entitlement, result|
          result[entitlement.billing_feature.key] = entitlement.value
        end

        render json: {
          plan: { id: subscription.billing_plan_id, code: subscription.billing_plan.code },
          entitlements: values
        }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end
    end
  end
end
