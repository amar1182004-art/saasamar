module V1
  module Support
    class AttachmentsController < ApplicationController
      include Authentication
      include TenantAuthorization

      def create
        upload = ::Support::AttachmentManager.issue_upload(
          store_id: params.require(:store_id),
          ticket_id: params.require(:ticket_id),
          filename: params.require(:filename),
          content_type: params.require(:content_type),
          byte_size: params.require(:byte_size),
          checksum_sha256: params[:checksum_sha256]
        )
        render json: {
          upload: {
            attachment_id: upload.attachment_id,
            object_key: upload.object_key,
            upload_url: upload.upload_url,
            expires_in: upload.expires_in
          }
        }, status: :created
      rescue TenantPermission::ForbiddenError
        render_forbidden
      rescue ::Support::AttachmentManager::InvalidAttachmentError, ActionController::ParameterMissing => error
        render_invalid(error)
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def complete
        attachment = ::Support::AttachmentManager.complete(
          store_id: params.require(:store_id),
          ticket_id: params.require(:ticket_id),
          attachment_id: params.require(:id)
        )
        render json: { attachment: serialize(attachment) }
      rescue TenantPermission::ForbiddenError
        render_forbidden
      rescue ::Support::AttachmentManager::InvalidAttachmentError => error
        render_invalid(error)
      rescue ::Support::AttachmentManager::UploadVerificationError => error
        render json: { error: "support_attachment_verification_failed", message: error.message }, status: :conflict
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def preview
        url = ::Support::AttachmentManager.preview_url(
          store_id: params.require(:store_id),
          ticket_id: params.require(:ticket_id),
          attachment_id: params.require(:id)
        )
        render json: { preview_url: url }
      rescue TenantPermission::ForbiddenError
        render_forbidden
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      private

      def serialize(attachment)
        {
          id: attachment.id,
          kind: attachment.kind,
          filename: attachment.filename,
          content_type: attachment.content_type,
          byte_size: attachment.byte_size,
          status: attachment.status
        }
      end

      def render_forbidden
        render json: { error: "permission_forbidden" }, status: :forbidden
      end

      def render_invalid(error)
        render json: { error: "support_attachment_invalid", message: error.message }, status: :unprocessable_entity
      end

      def render_not_found
        render json: { error: "support_attachment_not_found" }, status: :not_found
      end
    end
  end
end
