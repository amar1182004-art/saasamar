module Catalog
  class ProductMediaManager
    class MissingTenantContextError < StandardError; end
    class InvalidMediaError < StandardError; end
    class UploadVerificationError < StandardError; end

    IMAGE_TYPES = %w[image/jpeg image/png image/webp image/avif].freeze
    VIDEO_TYPES = %w[video/mp4 video/webm].freeze

    Upload = Data.define(:media_id, :object_key, :upload_url, :expires_in)

    def self.issue_upload(store_id:, product_id:, filename:, content_type:, byte_size:, product_variant_id: nil, checksum_sha256: nil, alt_text: nil, position: 0, metadata: {}, object_store: Storage::ObjectStore)
      require_context_and_permission!

      normalized_content_type = content_type.to_s.strip.downcase
      media_type = media_type_for(normalized_content_type)
      size = Integer(byte_size)
      validate_size!(media_type, size)
      validate_checksum!(checksum_sha256)

      store = Store.find(store_id)
      product = Product.find_by!(id: product_id, store_id: store.id)
      variant = nil
      if product_variant_id.present?
        variant = ProductVariant.find_by!(id: product_variant_id, store_id: store.id, product_id: product.id)
      end

      media_id = SecureRandom.uuid
      object_key = TenantStorageKey.build(
        tenant_id: Current.tenant_id,
        store_id: store.id,
        category: "products",
        object_id: media_id,
        filename: filename
      )

      ProductMedia.create!(
        id: media_id,
        tenant_id: Current.tenant_id,
        store_id: store.id,
        product_id: product.id,
        product_variant_id: variant&.id,
        media_type: media_type,
        object_key: object_key,
        content_type: normalized_content_type,
        byte_size: size,
        checksum_sha256: checksum_sha256.presence&.downcase,
        alt_text: alt_text,
        position: Integer(position),
        status: "pending",
        metadata: metadata
      )

      ttl = upload_ttl
      Upload.new(
        media_id: media_id,
        object_key: object_key,
        upload_url: object_store.presigned_put(key: object_key, content_type: normalized_content_type, expires_in: ttl),
        expires_in: ttl
      )
    rescue ArgumentError, TypeError
      raise InvalidMediaError, "invalid media size or position"
    end

    def self.complete(store_id:, product_id:, media_id:, width: nil, height: nil, duration_ms: nil, object_store: Storage::ObjectStore)
      require_context_and_permission!

      media = scoped_media(store_id: store_id, product_id: product_id, media_id: media_id)
      return media if media.status == "ready"

      head = object_store.head(key: media.object_key)
      actual_size = Integer(head.content_length)
      actual_content_type = head.content_type.to_s.split(";", 2).first.to_s.strip.downcase

      unless actual_size == media.byte_size && actual_content_type == media.content_type
        mark_failed_and_delete!(media, object_store)
        raise UploadVerificationError, "uploaded object does not match the declared media metadata"
      end

      media.update!(
        status: "ready",
        width: normalized_optional_integer(width),
        height: normalized_optional_integer(height),
        duration_ms: normalized_optional_integer(duration_ms)
      )
      media
    rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
      raise UploadVerificationError, "uploaded object was not found"
    end

    def self.destroy(store_id:, product_id:, media_id:, object_store: Storage::ObjectStore)
      require_context_and_permission!

      media = scoped_media(store_id: store_id, product_id: product_id, media_id: media_id)
      object_store.delete(key: media.object_key)
      media.destroy!
    end

    def self.preview_url(store_id:, product_id:, media_id:, object_store: Storage::ObjectStore)
      require_context_and_read_permission!

      media = scoped_media(store_id: store_id, product_id: product_id, media_id: media_id, status: "ready")
      object_store.presigned_get(key: media.object_key)
    end

    def self.scoped_media(store_id:, product_id:, media_id:, status: nil)
      store = Store.find(store_id)
      product = Product.find_by!(id: product_id, store_id: store.id)
      scope = ProductMedia.where(store_id: store.id, product_id: product.id)
      scope = scope.where(status: status) if status
      scope.find(media_id)
    end
    private_class_method :scoped_media

    def self.require_context_and_permission!
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      TenantPermission.require!(Current.membership, "catalog.manage")
    end
    private_class_method :require_context_and_permission!

    def self.require_context_and_read_permission!
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      TenantPermission.require!(Current.membership, "catalog.read")
    end
    private_class_method :require_context_and_read_permission!

    def self.media_type_for(content_type)
      return "image" if IMAGE_TYPES.include?(content_type)
      return "video" if VIDEO_TYPES.include?(content_type)

      raise InvalidMediaError, "unsupported product media content type"
    end
    private_class_method :media_type_for

    def self.validate_size!(media_type, byte_size)
      raise InvalidMediaError, "media size must be positive" unless byte_size.positive?

      max = media_type == "image" ? image_max_bytes : video_max_bytes
      raise InvalidMediaError, "media file is too large" if byte_size > max
    end
    private_class_method :validate_size!

    def self.validate_checksum!(checksum)
      return if checksum.blank?
      return if checksum.to_s.match?(/\A[0-9a-fA-F]{64}\z/)

      raise InvalidMediaError, "checksum_sha256 must be a 64-character hexadecimal digest"
    end
    private_class_method :validate_checksum!

    def self.image_max_bytes
      Integer(ENV.fetch("PRODUCT_IMAGE_MAX_BYTES", "20971520"))
    end
    private_class_method :image_max_bytes

    def self.video_max_bytes
      Integer(ENV.fetch("PRODUCT_VIDEO_MAX_BYTES", "262144000"))
    end
    private_class_method :video_max_bytes

    def self.upload_ttl
      Integer(ENV.fetch("PRODUCT_MEDIA_UPLOAD_TTL_SECONDS", "600"))
    end
    private_class_method :upload_ttl

    def self.normalized_optional_integer(value)
      return nil if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      raise InvalidMediaError, "invalid media dimensions or duration"
    end
    private_class_method :normalized_optional_integer

    def self.mark_failed_and_delete!(media, object_store)
      media.update!(status: "failed")
      object_store.delete(key: media.object_key)
    rescue Aws::S3::Errors::ServiceError
      nil
    end
    private_class_method :mark_failed_and_delete!
  end
end
