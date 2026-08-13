module V1
  module Catalog
    class CategoriesController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        TenantPermission.require!(Current.membership, "catalog.read")
        store = Store.find(params.require(:store_id))
        categories = Category.where(store_id: store.id).order(:position, :name)

        render json: { categories: categories.map { |category| serialize(category) } }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def create
        TenantPermission.require!(Current.membership, "catalog.manage")
        store = Store.find(params.require(:store_id))
        category = Category.create!(category_attributes.merge(
          tenant_id: Current.tenant_id,
          store_id: store.id
        ))

        render json: { category: serialize(category) }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "category_validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      end

      def update
        TenantPermission.require!(Current.membership, "catalog.manage")
        category = scoped_category
        category.update!(category_attributes)

        render json: { category: serialize(category) }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "category_validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      end

      def destroy
        TenantPermission.require!(Current.membership, "catalog.manage")
        scoped_category.update!(status: "archived")
        head :no_content
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      private

      def scoped_category
        store = Store.find(params.require(:store_id))
        Category.find_by!(id: params.require(:id), store_id: store.id)
      end

      def category_attributes
        params.require(:category).permit(
          :parent_id,
          :name,
          :slug,
          :description,
          :status,
          :position,
          metadata: {}
        ).to_h.symbolize_keys
      end

      def serialize(category)
        {
          id: category.id,
          store_id: category.store_id,
          parent_id: category.parent_id,
          name: category.name,
          slug: category.slug,
          description: category.description,
          status: category.status,
          position: category.position,
          metadata: category.metadata
        }
      end
    end
  end
end
