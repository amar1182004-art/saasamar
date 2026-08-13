module V1
  class StorefrontController < ApplicationController
    include Authentication
    include TenantAuthorization

    def show
      render json: { storefront: serialize(Storefront::ConfigurationManager.read(store_id: params.require(:store_id))) }
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    end

    def update
      attributes = storefront_attributes
      storefront = Storefront::ConfigurationManager.update(
        store_id: params.require(:store_id),
        status: attributes[:status],
        config: attributes[:config] || {}
      )

      render json: { storefront: serialize(storefront) }
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    rescue Storefront::ConfigurationManager::InvalidConfigurationError => error
      render json: { error: "storefront_validation_failed", details: error.message }, status: :unprocessable_entity
    end

    def publish
      storefront = Storefront::ConfigurationManager.publish(store_id: params.require(:store_id))
      render json: { storefront: serialize(storefront) }
    rescue TenantPermission::ForbiddenError
      render json: { error: "permission_forbidden" }, status: :forbidden
    rescue Storefront::ConfigurationManager::InvalidConfigurationError => error
      render json: { error: "storefront_validation_failed", details: error.message }, status: :unprocessable_entity
    end

    private

    def storefront_attributes
      params.require(:storefront).permit(:status, config: {}).to_h.deep_symbolize_keys
    end

    def serialize(storefront)
      {
        id: storefront.id,
        store_id: storefront.store_id,
        status: storefront.status,
        draft_config: storefront.draft_config,
        published_config: storefront.published_config,
        draft_version: storefront.draft_version,
        published_version: storefront.published_version,
        published_at: storefront.published_at,
        lock_version: storefront.lock_version
      }
    end
  end
end
