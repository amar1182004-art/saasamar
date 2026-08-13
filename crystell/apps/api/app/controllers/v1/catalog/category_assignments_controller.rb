module V1
  module Catalog
    class CategoryAssignmentsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def create
        TenantPermission.require!(Current.membership, "catalog.manage")
        product = scoped_product
        category = Category.find_by!(id: params.require(:category_id), store_id: product.store_id)
        assignment = ProductCategoryAssignment.create_or_find_by!(
          tenant_id: Current.tenant_id,
          store_id: product.store_id,
          product_id: product.id,
          category_id: category.id
        )
        assignment.update!(position: params[:position].to_i) if params.key?(:position)

        render json: {
          assignment: {
            id: assignment.id,
            product_id: assignment.product_id,
            category_id: assignment.category_id,
            position: assignment.position
          }
        }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def destroy
        TenantPermission.require!(Current.membership, "catalog.manage")
        product = scoped_product
        assignment = ProductCategoryAssignment.find_by!(
          id: params.require(:id),
          product_id: product.id,
          store_id: product.store_id
        )
        assignment.destroy!

        head :no_content
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      private

      def scoped_product
        store = Store.find(params.require(:store_id))
        Product.find_by!(id: params.require(:product_id), store_id: store.id)
      end
    end
  end
end
