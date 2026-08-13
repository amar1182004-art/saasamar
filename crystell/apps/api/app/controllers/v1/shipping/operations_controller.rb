module V1
  module Shipping
    class OperationsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def quotes
        quotes = ::Shipping::RateQuoter.call(
          checkout_session_id: params.require(:checkout_session_id),
          shipping_provider_account_id: params.require(:shipping_provider_account_id),
          destination: destination_params
        )

        render json: {
          quotes: quotes.map { |quote| serialize_quote(quote) }
        }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Shipping::RateQuoter::InvalidCheckoutError,
             ::Shipping::RateQuoter::InvalidDestinationError => error
        render json: { error: "invalid_shipping_quote_request", message: error.message }, status: :unprocessable_entity
      end

      def select_quote
        checkout = ::Shipping::QuoteSelector.call(
          checkout_session_id: params.require(:checkout_session_id),
          shipping_rate_quote_id: params.require(:shipping_rate_quote_id),
          shipping_address: shipping_address_params
        )

        render json: {
          checkout: {
            id: checkout.id,
            shipping_rate_quote_id: checkout.selected_shipping_rate_quote_id,
            shipping_cents: checkout.shipping_cents,
            total_cents: checkout.total_cents,
            currency: checkout.currency,
            shipping_address: checkout.shipping_address
          }
        }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Shipping::QuoteSelector::InvalidQuoteError => error
        render json: { error: "invalid_shipping_quote", message: error.message }, status: :unprocessable_entity
      end

      def create_shipment
        shipment = ::Shipping::ShipmentCreator.call(
          order_id: params.require(:order_id),
          idempotency_key: params.require(:idempotency_key)
        )

        render json: { shipment: serialize_shipment(shipment) }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Shipping::ShipmentCreator::InvalidOrderError,
             ::Shipping::ShipmentCreator::InvalidQuoteError => error
        render json: { error: "invalid_shipment", message: error.message }, status: :unprocessable_entity
      end

      private

      def destination_params
        params.require(:destination).permit(:country_code, :postal_code, :city, :state).to_h
      end

      def shipping_address_params
        params.require(:shipping_address).permit(
          :first_name, :last_name, :company, :phone,
          :address1, :address2, :city, :state, :postal_code, :country_code
        ).to_h
      end

      def serialize_quote(quote)
        {
          id: quote.id,
          provider_account_id: quote.shipping_provider_account_id,
          service_code: quote.service_code,
          service_name: quote.service_name,
          amount_cents: quote.amount_cents,
          currency: quote.currency,
          expires_at: quote.expires_at
        }
      end

      def serialize_shipment(shipment)
        {
          id: shipment.id,
          order_id: shipment.order_id,
          status: shipment.status,
          service_code: shipment.service_code,
          shipping_cost_cents: shipment.shipping_cost_cents,
          currency: shipment.currency,
          tracking_number: shipment.tracking_number,
          tracking_url: shipment.tracking_url,
          label_url: shipment.label_url
        }
      end
    end
  end
end
