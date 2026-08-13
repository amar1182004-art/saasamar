module V1
  module Billing
    class InvoicesController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        TenantPermission.require!(Current.membership, "billing.read")

        invoices = Invoice.order(created_at: :desc).limit(100)
        render json: {
          invoices: invoices.map do |invoice|
            {
              id: invoice.id,
              number: invoice.number,
              status: invoice.status,
              currency: invoice.currency,
              subtotal_cents: invoice.subtotal_cents,
              discount_cents: invoice.discount_cents,
              tax_cents: invoice.tax_cents,
              total_cents: invoice.total_cents,
              amount_paid_cents: invoice.amount_paid_cents,
              issued_at: invoice.issued_at,
              due_at: invoice.due_at,
              paid_at: invoice.paid_at
            }
          end
        }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end
    end
  end
end
