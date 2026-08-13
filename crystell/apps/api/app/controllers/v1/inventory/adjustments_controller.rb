module V1
  module Inventory
    class AdjustmentsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def create
        result = ::Inventory::Adjuster.call(
          store_id: params.require(:store_id),
          inventory_location_id: params.require(:inventory_location_id),
          product_variant_id: params.require(:product_variant_id),
          delta_on_hand: params.require(:delta_on_hand),
          reason: params.require(:reason),
          idempotency_key: params.require(:idempotency_key),
          metadata: metadata_params
        )

        render json: {
          adjustment: {
            recorded: result.recorded,
            ledger_entry_id: result.ledger_entry_id,
            on_hand: result.on_hand,
            reserved: result.reserved,
            available: result.available
          }
        }, status: result.recorded ? :created : :ok
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Inventory::Adjuster::InvalidAdjustmentError => error
        render json: { error: "invalid_inventory_adjustment", message: error.message }, status: :unprocessable_entity
      rescue ::Inventory::Adjuster::InsufficientStockError => error
        render json: { error: "inventory_adjustment_conflict", message: error.message }, status: :conflict
      rescue ::Inventory::Adjuster::IdempotencyConflictError => error
        render json: { error: "inventory_idempotency_conflict", message: error.message }, status: :conflict
      end

      private

      def metadata_params
        value = params[:metadata]
        return {} if value.blank?

        value.permit!.to_h
      end
    end
  end
end
