module Billing
  class AffiliateAttributor
    class MissingTenantContextError < StandardError; end
    class InvalidCodeError < StandardError; end
    class AlreadyAttributedError < StandardError; end

    Result = Data.define(:attribution_id, :affiliate_id, :code, :expires_at)

    def self.call(code:, attributed_at: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      affiliate_code = BillingAffiliateCode.includes(:billing_affiliate).find_by(code: code.to_s.strip.upcase)
      raise InvalidCodeError, "affiliate code is not available" unless affiliate_code&.active_at?(attributed_at)

      existing = BillingAffiliateAttribution.active.first
      if existing
        if existing.billing_affiliate_code_id == affiliate_code.id
          return Result.new(
            attribution_id: existing.id,
            affiliate_id: affiliate_code.billing_affiliate_id,
            code: affiliate_code.code,
            expires_at: existing.expires_at
          )
        end
        raise AlreadyAttributedError, "tenant already has an active affiliate attribution"
      end

      expires_at = attributed_at + ENV.fetch("AFFILIATE_ATTRIBUTION_DAYS", "30").to_i.days
      attribution = BillingAffiliateAttribution.create!(
        tenant_id: Current.tenant_id,
        billing_affiliate_code: affiliate_code,
        status: "active",
        attributed_at: attributed_at,
        expires_at: expires_at
      )

      BillingEvent.create!(
        tenant_id: Current.tenant_id,
        event_type: "affiliate.attributed",
        actor_user_id: Current.user&.id,
        subject_id: attribution.id,
        subject_type: "BillingAffiliateAttribution",
        metadata: {
          affiliate_id: affiliate_code.billing_affiliate_id,
          affiliate_code_id: affiliate_code.id,
          code: affiliate_code.code
        }
      )

      Result.new(
        attribution_id: attribution.id,
        affiliate_id: affiliate_code.billing_affiliate_id,
        code: affiliate_code.code,
        expires_at: expires_at
      )
    rescue ActiveRecord::RecordNotUnique
      raise AlreadyAttributedError, "tenant already has an active affiliate attribution"
    end
  end
end
