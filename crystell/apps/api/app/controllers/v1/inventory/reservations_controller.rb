module V1
  module Inventory
    class ReservationsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def create
        result = ::Inventory::ReservationManager.reserve(
          store_id: params.require(:store_id),
          inventory_location_id: params.require(:inventory_location_id),
          product_variant_id: params.require(:product_variant_id),
          quantity: params.require(:quantity),
          idempotency_key: params.require(:idempotency_key),
          expires_at: parse_time(params[:expires_at]),
          reference_type: params[:reference_type],
          reference_id: params[:reference_id],
          metadata: metadata_params
        )

        render_result(result, result.recorded ? :created : :ok)
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Inventory::ReservationManager::InvalidReservationError => error
        render json: { error: "invalid_inventory_reservation", message: error.message }, status: :unprocessable_entity
      rescue ::Inventory::ReservationManager::InsufficientStockError => error
        render json: { error: "insufficient_inventory", message: error.message }, status: :conflict
      rescue ::Inventory::ReservationManager::IdempotencyConflictError => error
        render json: { error: "idempotency_conflict", message: error.message }, status: :conflict
      end

      def release
        render_result(::Inventory::ReservationManager.release(reservation_id: params.require(:id)), :ok)
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Inventory::ReservationManager::InvalidTransitionError => error
        render json: { error: "reservation_transition_invalid", message: error.message }, status: :conflict
      end

      def consume
        render_result(::Inventory::ReservationManager.consume(reservation_id: params.require(:id)), :ok)
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Inventory::ReservationManager::InvalidTransitionError, ::Inventory::ReservationManager::InsufficientStockError => error
        render json: { error: "reservation_transition_invalid", message: error.message }, status: :conflict
      end

      def expire
        render_result(::Inventory::ReservationManager.expire(reservation_id: params.require(:id)), :ok)
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Inventory::ReservationManager::InvalidTransitionError => error
        render json: { error: "reservation_transition_invalid", message: error.message }, status: :conflict
      end

      private

      def render_result(result, status)
        render json: {
          reservation: {
            recorded: result.recorded,
            id: result.reservation_id,
            status: result.status,
            on_hand: result.on_hand,
            reserved: result.reserved,
            available: result.available
          }
        }, status: status
      end

      def metadata_params
        value = params[:metadata]
        return {} if value.blank?

        value.permit!.to_h
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
