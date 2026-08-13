module Control
  module V1
    class ContentController < BaseController
      def index
        documents = ControlPlane::ContentRegistry.list(kind: params[:kind], locale: params[:locale])
        render json: { content_documents: documents.map { |document| serialize_document(document) } }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::ContentRegistry::InvalidContentError => error
        render_invalid(error)
      end

      def show
        document = ControlPlane::ContentRegistry.read(key: params.require(:key), locale: params[:locale] || "en")
        render json: { content_document: serialize_document(document) }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::ContentRegistry::InvalidContentError => error
        render_invalid(error)
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def update
        attributes = content_attributes
        document = ControlPlane::ContentRegistry.update_draft(
          key: params.require(:key),
          kind: attributes.fetch(:kind),
          locale: attributes[:locale] || "en",
          content: attributes.fetch(:content),
          reason: attributes[:reason],
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        render json: { content_document: serialize_document(document) }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::ContentRegistry::InvalidContentError, ActionController::ParameterMissing => error
        render_invalid(error)
      end

      def publish
        attributes = publication_attributes
        document = ControlPlane::ContentRegistry.publish(
          key: params.require(:key),
          locale: attributes[:locale] || "en",
          reason: attributes[:reason],
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        render json: { content_document: serialize_document(document) }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::ContentRegistry::ElevationRequiredError
        render json: { error: "privilege_elevation_required" }, status: :conflict
      rescue ControlPlane::ContentRegistry::InvalidContentError, ActionController::ParameterMissing => error
        render_invalid(error)
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def rollback
        attributes = rollback_attributes
        document = ControlPlane::ContentRegistry.rollback(
          key: params.require(:key),
          version: attributes.fetch(:version),
          locale: attributes[:locale] || "en",
          reason: attributes[:reason],
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        render json: { content_document: serialize_document(document) }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::ContentRegistry::ElevationRequiredError
        render json: { error: "privilege_elevation_required" }, status: :conflict
      rescue ControlPlane::ContentRegistry::InvalidContentError, ActionController::ParameterMissing => error
        render_invalid(error)
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def versions
        versions = ControlPlane::ContentRegistry.versions(key: params.require(:key), locale: params[:locale] || "en")
        render json: { content_versions: versions.map { |version| serialize_version(version) } }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::ContentRegistry::InvalidContentError => error
        render_invalid(error)
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      private

      def content_attributes
        params.require(:content_document).permit(:kind, :locale, :reason, content: {}).to_h.deep_symbolize_keys
      end

      def publication_attributes
        params.require(:publication).permit(:locale, :reason).to_h.deep_symbolize_keys
      end

      def rollback_attributes
        params.require(:rollback).permit(:locale, :version, :reason).to_h.deep_symbolize_keys
      end

      def serialize_document(document)
        {
          id: document.id,
          key: document.key,
          kind: document.kind,
          locale: document.locale,
          draft_content: document.draft_content,
          published_content: document.published_content,
          draft_version: document.draft_version,
          published_version: document.published_version,
          published_at: document.published_at,
          lock_version: document.lock_version,
          updated_at: document.updated_at
        }
      end

      def serialize_version(version)
        {
          id: version.id,
          version: version.version,
          source: version.source,
          content: version.content,
          created_by_user_id: version.control_plane_user_id,
          created_at: version.created_at
        }
      end

      def render_forbidden
        render json: { error: "control_plane_forbidden" }, status: :forbidden
      end

      def render_invalid(error)
        render json: { error: "content_validation_failed", details: error.message }, status: :unprocessable_entity
      end

      def render_not_found
        render json: { error: "content_not_found" }, status: :not_found
      end
    end
  end
end
