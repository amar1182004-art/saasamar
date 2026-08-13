module V1
  module Inventory
    class LevelsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        TenantPermission.require!(Current.membership, "inventory.read")
        store = Store.find(params.require(:store_id))
        scope = InventoryLevel.where(store_id: store.id)
          .includes(:inventory_location, :product_variant)
          .order(:inventory_location_id, :product_variant_id)

        scope = scope.where(product_variant_id: params[:product_variant_id]) if params[:product_variant_id].present?
        scope = scope.where(inventory_location_id: params[:inventory_location_id]) if params[:inventory_location_id].present?

        render json: { levels: scope.limit(500).map { |level| serialize(level) } }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      private

      def serialize(level)
        {
          id: level.id,
          store_id: level.store_id,
          inventory_location_id: level.inventory_location_id,
          product_variant_id: level.product_variant_id,
          sku: level.product_variant.sku,
          on_hand: level.on_hand,
          reserved: level.reserved,
          available: level.available,
          updated_at: level.updated_at
        }
      end
    end
  end
end
