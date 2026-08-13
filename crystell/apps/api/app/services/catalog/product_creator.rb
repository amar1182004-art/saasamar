module Catalog
  class ProductCreator
    class MissingTenantContextError < StandardError; end
    class InvalidVariantsError < StandardError; end

    def self.call(store_id:, attributes:, variants:)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      TenantPermission.require!(Current.membership, "catalog.manage")
      raise InvalidVariantsError, "at least one variant is required" if variants.blank?

      store = Store.find(store_id)

      Product.transaction do
        product = Product.create!(
          tenant_id: Current.tenant_id,
          store_id: store.id,
          title: attributes.fetch(:title),
          slug: attributes.fetch(:slug),
          status: attributes.fetch(:status, "draft"),
          description: attributes[:description],
          vendor: attributes[:vendor],
          product_type: attributes[:product_type],
          seo_title: attributes[:seo_title],
          seo_description: attributes[:seo_description],
          published_at: attributes[:published_at],
          metadata: attributes.fetch(:metadata, {})
        )

        variants.each_with_index do |variant_attributes, position|
          product.product_variants.create!(
            tenant_id: Current.tenant_id,
            store_id: store.id,
            title: variant_attributes.fetch(:title),
            sku: variant_attributes[:sku],
            barcode: variant_attributes[:barcode],
            currency: variant_attributes.fetch(:currency),
            price_cents: variant_attributes.fetch(:price_cents, 0),
            compare_at_price_cents: variant_attributes[:compare_at_price_cents],
            cost_cents: variant_attributes[:cost_cents],
            position: variant_attributes.fetch(:position, position),
            taxable: variant_attributes.fetch(:taxable, true),
            track_inventory: variant_attributes.fetch(:track_inventory, true),
            weight_grams: variant_attributes[:weight_grams],
            status: variant_attributes.fetch(:status, "active"),
            option_values: variant_attributes.fetch(:option_values, {}),
            metadata: variant_attributes.fetch(:metadata, {})
          )
        end

        product
      end
    end
  end
end
