module Notifications
  class Inbox
    class InvalidNotificationError < StandardError; end

    def self.list
      require_context!
      TenantPermission.require!(Current.membership, "notifications.read")
      Notification.where(user_id: Current.user.id).order(created_at: :desc, id: :desc).limit(100)
    end

    def self.publish(user_id:, kind:, title:, body:, store_id: nil, action_url: nil, metadata: {})
      raise InvalidNotificationError, "tenant context is required" if Current.tenant_id.blank?
      membership = Membership.find_by!(user_id: user_id, status: "active")
      store = Store.find(store_id) if store_id.present?
      Notification.create!(
        tenant_id: Current.tenant_id,
        store_id: store&.id,
        user_id: membership.user_id,
        kind: kind,
        title: title,
        body: body,
        action_url: action_url,
        metadata: metadata
      )
    end

    def self.mark_read(notification_id:)
      require_context!
      TenantPermission.require!(Current.membership, "notifications.read")
      notification = Notification.where(user_id: Current.user.id).find(notification_id)
      notification.update!(read_at: Time.current) if notification.read_at.nil?
      notification
    end

    def self.require_context!
      raise InvalidNotificationError, "tenant context is required" if Current.tenant_id.blank? || Current.user.blank?
    end
    private_class_method :require_context!
  end
end
