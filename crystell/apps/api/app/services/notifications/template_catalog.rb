module Notifications
  class TemplateCatalog
    class InvalidTemplateError < StandardError; end

    def self.list(store_id:)
      require_context_and_permission!("notifications.read")
      NotificationTemplate.where(store_id: Store.find(store_id).id).order(:key, :channel, :locale).limit(500)
    end

    def self.upsert(store_id:, key:, channel:, locale:, subject:, body:, status:, variables:)
      require_context_and_permission!("notifications.manage")
      store = Store.find(store_id)
      normalized_key = key.to_s.strip.downcase
      normalized_channel = channel.to_s.strip.downcase
      normalized_locale = locale.to_s.strip.downcase
      template = NotificationTemplate.find_or_initialize_by(
        tenant_id: Current.tenant_id,
        store_id: store.id,
        key: normalized_key,
        channel: normalized_channel,
        locale: normalized_locale
      )
      template.assign_attributes(
        subject: subject,
        body: body,
        status: status,
        variables: Array(variables).map(&:to_s).uniq
      )
      template.save!
      template
    rescue ActiveRecord::RecordInvalid => error
      raise InvalidTemplateError, error.record.errors.full_messages.join(", ")
    end

    def self.require_context_and_permission!(permission)
      raise InvalidTemplateError, "tenant context is required" if Current.tenant_id.blank?

      TenantPermission.require!(Current.membership, permission)
    end
    private_class_method :require_context_and_permission!
  end
end
