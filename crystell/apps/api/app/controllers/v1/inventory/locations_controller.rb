module V1
  module Inventory
    class LocationsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        TenantPermission.require!(Current.membership, "inventory.read")
        store = Store.find(params.require(:store_id))
        locations = InventoryLocation.where(store_id: store.id).order(:priority, :name)

        render json: { locations: locations.map { |location| serialize(location) } }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def create
        TenantPermission.require!(Current.membership, "inventory.manage")
        store = Store.find(params.require(:store_id))
        location = InventoryLocation.create!(location_attributes.merge(
          tenant_id: Current.tenant_id,
          store_id: store.id
        ))

        render json: { location: serialize(location) }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "inventory_location_validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      end

      def update
        TenantPermission.require!(Current.membership, "inventory.manage")
        location = scoped_location
        location.update!(location_attributes)

        render json: { location: serialize(location) }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "inventory_location_validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      end

      def destroy
        TenantPermission.require!(Current.membership, "inventory.manage")
        scoped_location.update!(status: "inactive")
        head :no_content
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      private

      def scoped_location
        store = Store.find(params.require(:store_id))
        InventoryLocation.find_by!(id: params.require(:id), store_id: store.id)
      end

      def location_attributes
        params.require(:location).permit(
          :name,
          :code,
          :status,
          :priority,
          address: {},
          metadata: {}
        ).to_h.symbolize_keys
      end

      def serialize(location)
        {
          id: location.id,
          store_id: location.store_id,
          name: location.name,
          code: location.code,
          status: location.status,
          priority: location.priority,
          address: location.address,
          metadata: location.metadata
        }
      end
    end
  end
end
