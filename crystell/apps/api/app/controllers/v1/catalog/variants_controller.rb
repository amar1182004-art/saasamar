module V1
  module Catalog
    class VariantsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def create
        TenantPermission.require!(Current.membership, "catalog.manage")
        product = scoped_product
        variant = product.product_variants.create!(variant_attributes.merge(
          tenant_id: Current.tenant_id,
          store_id: product.store_id
        ))

        render json: { variant: serialize(variant) }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "catalog_validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      end

      def update
        TenantPermission.require!(Current.membership, "catalog.manage")
        variant = scoped_variant
        variant.update!(variant_attributes)

        render json: { variant: serialize(variant) }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "catalog_validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      end

      def destroy
        TenantPermission.require!(Current.membership, "catalog.manage")
        scoped_variant.update!(status: "archived")
        head :no_content
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      private

      def scoped_product
        store = Store.find(params.require(:store_id))
        Product.find_by!(id: params.require(:product_id), store_id: store.id)
      end

      def scoped_variant
        product = scoped_product
        ProductVariant.find_by!(id: params.require(:id), product_id: product.id, store_id: product.store_id)
      end

      def variant_attributes
        params.require(:variant).permit(
          :title,
          :sku,
          :barcode,
          :currency,
          :price_cents,
          :compare_at_price_cents,
          :cost_cents,
          :position,
          :taxable,
          :track_inventory,
          :weight_grams,
          :status,
          option_values: {},
          metadata: {}
        ).to_h.symbolize_keys
      end

      def serialize(variant)
        {
          id: variant.id,
          product_id: variant.product_id,
          title: variant.title,
          sku: variant.sku,
          barcode: variant.barcode,
          currency: variant.currency,
          price_cents: variant.price_cents,
          compare_at_price_cents: variant.compare_at_price_cents,
          cost_cents: variant.cost_cents,
          position: variant.position,
          taxable: variant.taxable,
          track_inventory: variant.track_inventory,
          weight_grams: variant.weight_grams,
          status: variant.status,
          option_values: variant.option_values,
          metadata: variant.metadata
        }
      end
    end
  end
end
