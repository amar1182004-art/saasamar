module Billing
  class CouponQuote
    class MissingTenantContextError < StandardError; end
    class InvalidCouponError < StandardError; end

    Result = Data.define(:coupon_id, :code, :discount_cents)

    def self.call(code:, subscription:, subtotal_cents:, at: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      raise InvalidCouponError, "subtotal must be non-negative" if subtotal_cents.to_i.negative?

      coupon = BillingCoupon.find_by(code: code.to_s.strip.upcase)
      raise InvalidCouponError, "coupon is not available" unless coupon&.active_at?(at)
      raise InvalidCouponError, "coupon does not apply to this plan" if coupon.billing_plan_id.present? && coupon.billing_plan_id != subscription.billing_plan_id
      raise InvalidCouponError, "coupon currency does not match subscription" if coupon.discount_type == "fixed" && coupon.currency != subscription.currency
      raise InvalidCouponError, "coupon redemption limit reached" unless globally_available?(coupon.id)

      tenant_redemptions = BillingCouponRedemption.where(billing_coupon_id: coupon.id).count
      raise InvalidCouponError, "tenant coupon redemption limit reached" if tenant_redemptions >= coupon.per_tenant_limit

      discount = if coupon.discount_type == "percentage"
        (subtotal_cents.to_i * coupon.percentage_basis_points / 10_000.0).floor
      else
        coupon.fixed_amount_cents
      end
      discount = [discount, subtotal_cents.to_i].min

      Result.new(coupon_id: coupon.id, code: coupon.code, discount_cents: discount)
    end

    def self.globally_available?(coupon_id)
      connection = ApplicationRecord.connection
      result = connection.select_value(
        "SELECT crystell.billing_coupon_globally_available(#{connection.quote(coupon_id)}::uuid)"
      )
      ActiveModel::Type::Boolean.new.cast(result)
    end
    private_class_method :globally_available?
  end
end
