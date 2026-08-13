module V1
  module Catalog
    class MediaController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        TenantPermission.require!(Current.membership, "catalog.read")
        product = scoped_product
        media = ProductMedia.where(product_id: product.id, store_id: product.store_id).order(:position, :created_at)

        render json: { media: media.map { |item| serialize(item) } }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def create
        upload = ::Catalog::ProductMediaManager.issue_upload(
          store_id: params.require(:store_id),
          product_id: params.require(:product_id),
          product_variant_id: params[:product_variant_id],
          filename: params.require(:filename),
          content_type: params.require(:content_type),
          byte_size: params.require(:byte_size),
          checksum_sha256: params[:checksum_sha256],
          alt_text: params[:alt_text],
          position: params.fetch(:position, 0),
          metadata: metadata_params
        )

        render json: {
          upload: {
            media_id: upload.media_id,
            object_key: upload.object_key,
            upload_url: upload.upload_url,
            expires_in: upload.expires_in
          }
        }, status: :created
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Catalog::ProductMediaManager::InvalidMediaError => error
        render json: { error: "invalid_product_media", message: error.message }, status: :unprocessable_entity
      end

      def complete
        media = ::Catalog::ProductMediaManager.complete(
          store_id: params.require(:store_id),
          product_id: params.require(:product_id),
          media_id: params.require(:id),
          width: params[:width],
          height: params[:height],
          duration_ms: params[:duration_ms]
        )

        render json: { media: serialize(media) }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      rescue ::Catalog::ProductMediaManager::InvalidMediaError => error
        render json: { error: "invalid_product_media", message: error.message }, status: :unprocessable_entity
      rescue ::Catalog::ProductMediaManager::UploadVerificationError => error
        render json: { error: "product_media_verification_failed", message: error.message }, status: :conflict
      end

      def preview
        url = ::Catalog::ProductMediaManager.preview_url(
          store_id: params.require(:store_id),
          product_id: params.require(:product_id),
          media_id: params.require(:id)
        )
        render json: { preview_url: url }
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def destroy
        ::Catalog::ProductMediaManager.destroy(
          store_id: params.require(:store_id),
          product_id: params.require(:product_id),
          media_id: params.require(:id)
        )
        head :no_content
      rescue TenantPermission::ForbiddenError
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      private

      def scoped_product
        store = Store.find(params.require(:store_id))
        Product.find_by!(id: params.require(:product_id), store_id: store.id)
      end

      def metadata_params
        value = params[:metadata]
        return {} if value.blank?

        value.permit!.to_h
      end

      def serialize(media)
        {
          id: media.id,
          product_id: media.product_id,
          product_variant_id: media.product_variant_id,
          media_type: media.media_type,
          content_type: media.content_type,
          byte_size: media.byte_size,
          checksum_sha256: media.checksum_sha256,
          alt_text: media.alt_text,
          position: media.position,
          status: media.status,
          width: media.width,
          height: media.height,
          duration_ms: media.duration_ms,
          metadata: media.metadata
        }
      end
    end
  end
end
