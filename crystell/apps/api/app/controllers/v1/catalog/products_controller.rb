module V1
  module Catalog
    class ProductsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        TenantPermission.require!(Current.membership, "catalog.read")
        store = Store.find(params.require(:store_id))
        limit = [[params.fetch(:limit, 50).to_i, 1].max, 100].min
        products = Product.where(store_id: store.id)
          .includes(:product_variants)
          .order(created_at: :desc, id: :desc)
          .limit(limit)

        render json: { products: products.map { |product| serialize(product) } }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def show
        TenantPermission.require!(Current.membership, "catalog.read")
        product = scoped_product

        render json: { product: serialize(product) }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def create
        product = ::Catalog::ProductCreator.call(
          store_id: params.require(:store_id),
          attributes: product_attributes,
          variants: variant_attributes
        )

        render json: { product: serialize(product) }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ActionController::ParameterMissing, KeyError => error
        render json: { error: "invalid_catalog_payload", message: error.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "catalog_validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      rescue ::Catalog::ProductCreator::InvalidVariantsError => error
        render json: { error: "invalid_variants", message: error.message }, status: :unprocessable_entity
      end

      def update
        TenantPermission.require!(Current.membership, "catalog.manage")
        product = scoped_product
        product.update!(product_attributes.except(:published_at).merge(published_at: parsed_published_at))

        render json: { product: serialize(product) }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "catalog_validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      end

      def destroy
        TenantPermission.require!(Current.membership, "catalog.manage")
        product = scoped_product

        Product.transaction do
          product.update!(status: "archived")
          product.product_variants.where.not(status: "archived").update_all(status: "archived", updated_at: Time.current)
        end

        head :no_content
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      private

      def scoped_product
        store = Store.find(params.require(:store_id))
        Product.includes(:product_variants).find_by!(id: params.require(:id), store_id: store.id)
      end

      def product_attributes
        permitted = params.require(:product).permit(
          :title,
          :slug,
          :status,
          :description,
          :vendor,
          :product_type,
          :seo_title,
          :seo_description,
          :published_at,
          metadata: {}
        ).to_h.symbolize_keys

        permitted[:published_at] = parse_time(permitted[:published_at]) if permitted.key?(:published_at)
        permitted
      end

      def variant_attributes
        params.require(:variants).map do |variant|
          variant.permit(
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
      end

      def parsed_published_at
        value = product_attributes[:published_at]
        value.nil? || value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) ? value : parse_time(value)
      end

      def parse_time(value)
        return nil if value.blank?
        return value if value.respond_to?(:to_time)

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def serialize(product)
        {
          id: product.id,
          store_id: product.store_id,
          title: product.title,
          slug: product.slug,
          status: product.status,
          description: product.description,
          vendor: product.vendor,
          product_type: product.product_type,
          seo_title: product.seo_title,
          seo_description: product.seo_description,
          published_at: product.published_at,
          variants: product.product_variants.sort_by(&:position).map do |variant|
            {
              id: variant.id,
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
              option_values: variant.option_values
            }
          end
        }
      end
    end
  end
end
