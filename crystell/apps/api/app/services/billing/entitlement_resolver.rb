module Billing
  class EntitlementResolver
    class MissingTenantContextError < StandardError; end

    Result = Data.define(:feature_key, :value, :value_type, :plan_code, :subscription_id) do
      def enabled?
        case value_type
        when "boolean"
          value == true || value == { "enabled" => true }
        else
          !value.nil?
        end
      end

      def limit
        return nil unless value.is_a?(Hash)

        value["limit"]
      end
    end

    def self.call(feature_key:)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      normalized_key = feature_key.to_s.strip.downcase
      subscription = Subscription.current.order(current_period_end: :desc).first
      return Result.new(feature_key: normalized_key, value: nil, value_type: nil, plan_code: nil, subscription_id: nil) unless subscription

      entitlement = BillingEntitlement
        .joins(:billing_feature)
        .includes(:billing_feature, :billing_plan)
        .find_by(
          billing_plan_id: subscription.billing_plan_id,
          billing_features: { key: normalized_key }
        )

      return Result.new(feature_key: normalized_key, value: nil, value_type: nil, plan_code: subscription.billing_plan.code, subscription_id: subscription.id) unless entitlement

      Result.new(
        feature_key: normalized_key,
        value: entitlement.value,
        value_type: entitlement.billing_feature.value_type,
        plan_code: entitlement.billing_plan.code,
        subscription_id: subscription.id
      )
    end
  end
end
