module V1
  module Notifications
    class TemplatesController < ApplicationController
      include Authentication
      include TenantAuthorization

      def index
        templates = ::Notifications::TemplateCatalog.list(store_id: params.require(:store_id))
        render json: { notification_templates: templates.map { |template| serialize(template) } }
      rescue TenantPermission::ForbiddenError
        render_forbidden
      end

      def update
        template = ::Notifications::TemplateCatalog.upsert(
          store_id: params.require(:store_id),
          key: params.require(:key),
          channel: params.require(:channel),
          locale: params.fetch(:locale, "ar"),
          subject: params[:subject],
          body: params.require(:body),
          status: params.fetch(:status, "draft"),
          variables: params.fetch(:variables, [])
        )
        render json: { notification_template: serialize(template) }
      rescue TenantPermission::ForbiddenError
        render_forbidden
      rescue ::Notifications::TemplateCatalog::InvalidTemplateError, ActionController::ParameterMissing => error
        render json: { error: "notification_template_invalid", message: error.message }, status: :unprocessable_entity
      end

      private

      def serialize(template)
        {
          id: template.id,
          key: template.key,
          channel: template.channel,
          locale: template.locale,
          subject: template.subject,
          body: template.body,
          status: template.status,
          variables: template.variables,
          updated_at: template.updated_at
        }
      end

      def render_forbidden
        render json: { error: "permission_forbidden" }, status: :forbidden
      end
    end
  end
end
