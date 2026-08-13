module Billing
  class UsageMeter
    class MissingTenantContextError < StandardError; end
    class MissingSubscriptionError < StandardError; end
    class UnknownFeatureError < StandardError; end
    class InvalidQuantityError < StandardError; end

    Result = Data.define(:recorded, :usage_event_id, :total_quantity, :period_start, :period_end)

    def self.call(feature_key:, quantity:, idempotency_key:, occurred_at: Time.current, metadata: {})
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      raise InvalidQuantityError, "idempotency key is required" if idempotency_key.blank?

      decimal_quantity = BigDecimal(quantity.to_s)
      raise InvalidQuantityError, "quantity must be positive" unless decimal_quantity.positive?

      feature = BillingFeature.find_by(key: feature_key.to_s.strip.downcase)
      raise UnknownFeatureError, "billing feature does not exist" unless feature

      subscription = Subscription.where(status: %w[trialing active past_due]).order(current_period_end: :desc).first
      raise MissingSubscriptionError, "tenant does not have a metered subscription" unless subscription

      event = nil
      total_quantity = nil

      ApplicationRecord.transaction do
        event = UsageEvent.create!(
          tenant_id: Current.tenant_id,
          billing_feature: feature,
          idempotency_key: idempotency_key,
          quantity: decimal_quantity,
          occurred_at: occurred_at,
          metadata: metadata
        )

        total_quantity = increment_total!(
          feature_id: feature.id,
          period_start: subscription.current_period_start,
          period_end: subscription.current_period_end,
          quantity: decimal_quantity
        )
      end

      Result.new(
        recorded: true,
        usage_event_id: event.id,
        total_quantity: total_quantity,
        period_start: subscription.current_period_start,
        period_end: subscription.current_period_end
      )
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/usage_events.*idempotency|index_usage_events_on_tenant_id_and_idempotency_key/i)

      existing = UsageEvent.find_by!(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
      total = UsageTotal.find_by(
        tenant_id: Current.tenant_id,
        billing_feature_id: existing.billing_feature_id,
        period_start: subscription.current_period_start,
        period_end: subscription.current_period_end
      )

      Result.new(
        recorded: false,
        usage_event_id: existing.id,
        total_quantity: total&.quantity || 0,
        period_start: subscription.current_period_start,
        period_end: subscription.current_period_end
      )
    end

    def self.increment_total!(feature_id:, period_start:, period_end:, quantity:)
      connection = ApplicationRecord.connection
      sql = <<~SQL
        INSERT INTO usage_totals (
          id, tenant_id, billing_feature_id, period_start, period_end, quantity, created_at, updated_at
        ) VALUES (
          gen_random_uuid(),
          #{connection.quote(Current.tenant_id)},
          #{connection.quote(feature_id)},
          #{connection.quote(period_start)},
          #{connection.quote(period_end)},
          #{connection.quote(quantity)},
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        )
        ON CONFLICT (tenant_id, billing_feature_id, period_start, period_end)
        DO UPDATE SET
          quantity = usage_totals.quantity + EXCLUDED.quantity,
          updated_at = CURRENT_TIMESTAMP
        RETURNING quantity
      SQL

      connection.select_value(sql).to_d
    end
    private_class_method :increment_total!
  end
end
