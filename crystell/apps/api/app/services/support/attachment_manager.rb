module Support
  class AttachmentManager
    class InvalidAttachmentError < StandardError; end
    class UploadVerificationError < StandardError; end

    IMAGE_TYPES = %w[image/jpeg image/png image/webp image/avif image/gif].freeze
    VIDEO_TYPES = %w[video/mp4 video/webm video/quicktime].freeze
    FILE_TYPES = %w[application/pdf text/plain text/csv application/zip].freeze

    Upload = Data.define(:attachment_id, :object_key, :upload_url, :expires_in)

    def self.issue_upload(store_id:, ticket_id:, filename:, content_type:, byte_size:, checksum_sha256: nil, object_store: Storage::ObjectStore)
      ticket = TicketDesk.read(store_id: store_id, ticket_id: ticket_id)
      normalized_type = content_type.to_s.strip.downcase
      kind = kind_for!(normalized_type)
      size = Integer(byte_size)
      validate_size!(kind, size)
      validate_checksum!(checksum_sha256)
      safe_filename = File.basename(filename.to_s).first(180)
      raise InvalidAttachmentError, "filename is required" if safe_filename.blank? || safe_filename == "."

      id = SecureRandom.uuid
      object_key = TenantStorageKey.build(
        tenant_id: Current.tenant_id,
        store_id: ticket.store_id,
        category: "support",
        object_id: id,
        filename: safe_filename
      )
      attachment = SupportAttachment.create!(
        id: id,
        tenant_id: Current.tenant_id,
        store_id: ticket.store_id,
        support_ticket_id: ticket.id,
        created_by_user_id: Current.user.id,
        kind: kind,
        object_key: object_key,
        filename: safe_filename,
        content_type: normalized_type,
        byte_size: size,
        checksum_sha256: checksum_sha256.presence&.downcase,
        status: "pending"
      )
      ttl = upload_ttl
      Upload.new(
        attachment_id: attachment.id,
        object_key: object_key,
        upload_url: object_store.presigned_put(key: object_key, content_type: normalized_type, expires_in: ttl),
        expires_in: ttl
      )
    rescue ArgumentError, TypeError
      raise InvalidAttachmentError, "attachment size is invalid"
    end

    def self.complete(store_id:, ticket_id:, attachment_id:, object_store: Storage::ObjectStore)
      ticket = TicketDesk.read(store_id: store_id, ticket_id: ticket_id)
      attachment = SupportAttachment.find_by!(
        id: attachment_id,
        support_ticket_id: ticket.id,
        store_id: ticket.store_id,
        created_by_user_id: Current.user.id
      )
      return attachment if attachment.status == "ready"

      head = object_store.head(key: attachment.object_key)
      actual_size = Integer(head.content_length)
      actual_type = head.content_type.to_s.split(";", 2).first.to_s.strip.downcase
      unless actual_size == attachment.byte_size && actual_type == attachment.content_type
        fail_and_delete!(attachment, object_store)
        raise UploadVerificationError, "uploaded attachment does not match its declaration"
      end

      attachment.update!(status: "ready")
      attachment
    rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
      raise UploadVerificationError, "uploaded attachment was not found"
    end

    def self.preview_url(store_id:, ticket_id:, attachment_id:, object_store: Storage::ObjectStore)
      ticket = TicketDesk.read(store_id: store_id, ticket_id: ticket_id)
      attachment = SupportAttachment.ready.find_by!(
        id: attachment_id,
        support_ticket_id: ticket.id,
        store_id: ticket.store_id
      )
      object_store.presigned_get(key: attachment.object_key)
    end

    def self.kind_for!(content_type)
      return "image" if IMAGE_TYPES.include?(content_type)
      return "video" if VIDEO_TYPES.include?(content_type)
      return "file" if FILE_TYPES.include?(content_type)

      raise InvalidAttachmentError, "unsupported support attachment content type"
    end
    private_class_method :kind_for!

    def self.validate_size!(kind, size)
      raise InvalidAttachmentError, "attachment size must be positive" unless size.positive?

      max = kind == "video" ? video_max_bytes : file_max_bytes
      raise InvalidAttachmentError, "support attachment is too large" if size > max
    end
    private_class_method :validate_size!

    def self.validate_checksum!(checksum)
      return if checksum.blank? || checksum.to_s.match?(/\A[0-9a-fA-F]{64}\z/)

      raise InvalidAttachmentError, "checksum_sha256 must be hexadecimal"
    end
    private_class_method :validate_checksum!

    def self.upload_ttl
      Integer(ENV.fetch("SUPPORT_ATTACHMENT_UPLOAD_TTL_SECONDS", "600"))
    end
    private_class_method :upload_ttl

    def self.file_max_bytes
      Integer(ENV.fetch("SUPPORT_FILE_MAX_BYTES", "26214400"))
    end
    private_class_method :file_max_bytes

    def self.video_max_bytes
      Integer(ENV.fetch("SUPPORT_VIDEO_MAX_BYTES", "262144000"))
    end
    private_class_method :video_max_bytes

    def self.fail_and_delete!(attachment, object_store)
      attachment.update!(status: "failed")
      object_store.delete(key: attachment.object_key)
    rescue Aws::S3::Errors::ServiceError
      nil
    end
    private_class_method :fail_and_delete!
  end
end
