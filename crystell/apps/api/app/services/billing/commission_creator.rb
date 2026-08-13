module Billing
  class CommissionCreator
    class MissingTenantContextError < StandardError; end
    class InvalidInvoiceError < StandardError; end
    class MissingAttributionError < StandardError; end
    class InvalidAffiliateError < StandardError; end

    Result = Data.define(:commission_id, :affiliate_id, :amount_cents, :currency, :status)

    def self.call(invoice_id:, earned_at: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      invoice = Invoice.find_by(id: invoice_id)
      raise InvalidInvoiceError, "invoice must be paid before commission is earned" unless invoice&.status == "paid"

      existing = BillingCommission.find_by(invoice_id: invoice.id)
      return result_for(existing) if existing

      attribution = BillingAffiliateAttribution
        .where(status: %w[active converted])
        .includes(billing_affiliate_code: :billing_affiliate)
        .order(attributed_at: :desc)
        .first
      raise MissingAttributionError, "tenant does not have an eligible affiliate attribution" unless attribution
      raise MissingAttributionError, "affiliate attribution has expired" if attribution.expires_at && attribution.expires_at <= earned_at

      affiliate = attribution.billing_affiliate_code.billing_affiliate
      raise InvalidAffiliateError, "affiliate is not active" unless affiliate.status == "active"

      amount_cents = commission_amount(affiliate: affiliate, invoice: invoice)

      commission = BillingCommission.transaction do
        created = BillingCommission.create!(
          tenant_id: Current.tenant_id,
          billing_affiliate: affiliate,
          billing_affiliate_attribution: attribution,
          invoice: invoice,
          currency: invoice.currency,
          basis_cents: invoice.total_cents,
          amount_cents: amount_cents,
          status: "pending",
          earned_at: earned_at
        )

        if attribution.status == "active"
          attribution.update!(
            status: "converted",
            converted_subscription: invoice.subscription,
            converted_at: earned_at
          )
        end

        BillingEvent.create!(
          tenant_id: Current.tenant_id,
          event_type: "affiliate.commission_earned",
          subject_id: created.id,
          subject_type: "BillingCommission",
          metadata: {
            affiliate_id: affiliate.id,
            invoice_id: invoice.id,
            basis_cents: invoice.total_cents,
            amount_cents: amount_cents,
            currency: invoice.currency
          }
        )

        created
      end

      result_for(commission)
    rescue ActiveRecord::RecordNotUnique
      existing = BillingCommission.find_by!(invoice_id: invoice.id)
      result_for(existing)
    end

    def self.commission_amount(affiliate:, invoice:)
      if affiliate.commission_type == "percentage"
        (invoice.total_cents * affiliate.percentage_basis_points / 10_000.0).floor
      else
        raise InvalidAffiliateError, "affiliate commission currency does not match invoice" unless affiliate.currency == invoice.currency

        affiliate.fixed_amount_cents
      end
    end
    private_class_method :commission_amount

    def self.result_for(commission)
      Result.new(
        commission_id: commission.id,
        affiliate_id: commission.billing_affiliate_id,
        amount_cents: commission.amount_cents,
        currency: commission.currency,
        status: commission.status
      )
    end
    private_class_method :result_for
  end
end
