module V1
  class NotificationsController < ApplicationController
    include Authentication
    include TenantAuthorization

    def index
      notifications = ::Notifications::Inbox.list
      render json: { notifications: notifications.map { |notification| serialize(notification) } }
    rescue TenantPermission::ForbiddenError
      render_forbidden
    end

    def read
      notification = ::Notifications::Inbox.mark_read(notification_id: params.require(:id))
      render json: { notification: serialize(notification) }
    rescue TenantPermission::ForbiddenError
      render_forbidden
    rescue ActiveRecord::RecordNotFound
      render json: { error: "notification_not_found" }, status: :not_found
    end

    private

    def serialize(notification)
      {
        id: notification.id,
        kind: notification.kind,
        title: notification.title,
        body: notification.body,
        action_url: notification.action_url,
        read_at: notification.read_at,
        created_at: notification.created_at
      }
    end

    def render_forbidden
      render json: { error: "permission_forbidden" }, status: :forbidden
    end
  end
end
