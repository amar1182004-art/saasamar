require "uri"

module Notifications
  class DeliveryQueue
    class InvalidDeliveryError < StandardError; end
    class IdempotencyConflictError < StandardError; end

    def self.call(store_id:, template_key:, channel:, locale:, recipient:, variables:, idempotency_key:, user_id: nil, provider_key: nil)
      raise InvalidDeliveryError, "tenant context is required" if Current.tenant_id.blank?
      TenantPermission.require!(Current.membership, "notifications.manage")
      store = Store.find(store_id)
      normalized_channel = channel.to_s.downcase
      normalized_recipient = normalize_recipient!(normalized_channel, recipient)
      key = idempotency_key.to_s.strip
      raise InvalidDeliveryError, "idempotency key is required" if key.blank? || key.length > 160

      template = NotificationTemplate.find_by!(
        store_id: store.id,
        key: template_key.to_s.downcase,
        channel: normalized_channel,
        locale: locale.to_s.downcase,
        status: "active"
      )
      account_scope = CommunicationProviderAccount.where(store_id: store.id, channel: normalized_channel, status: "active")
      account_scope = account_scope.where(provider_key: provider_key.to_s) if provider_key.present?
      account = account_scope.order(:created_at).first!
      rendered = TemplateRenderer.call(template: template, variables: variables)
      fingerprint = Communications::CredentialVault.fingerprint("#{normalized_channel}:#{normalized_recipient}")
      recipient_user_id = user_id.present? ? Membership.find_by!(user_id: user_id, status: "active").user_id : nil

      existing = NotificationDelivery.find_by(store_id: store.id, idempotency_key: key)
      if existing
        same = existing.notification_template_id == template.id && existing.destination_fingerprint == fingerprint
        raise IdempotencyConflictError, "idempotency key was used for another delivery" unless same

        return existing
      end

      delivery = begin
        NotificationDelivery.create!(
          tenant_id: Current.tenant_id,
          store_id: store.id,
          notification_template_id: template.id,
          communication_provider_account_id: account.id,
          user_id: recipient_user_id,
          channel: normalized_channel,
          recipient_ciphertext: Communications::CredentialVault.encrypt(normalized_recipient, purpose: "notification-recipient"),
          destination_fingerprint: fingerprint,
          payload_ciphertext: Communications::CredentialVault.encrypt(
            { "subject" => rendered.subject, "body" => rendered.body },
            purpose: "notification-payload"
          ),
          status: "queued",
          idempotency_key: key
        )
      rescue ActiveRecord::RecordNotUnique
        raced = NotificationDelivery.find_by!(store_id: store.id, idempotency_key: key)
        same = raced.notification_template_id == template.id && raced.destination_fingerprint == fingerprint
        raise IdempotencyConflictError, "idempotency key was used for another delivery" unless same

        return raced
      end
      NotificationDeliveryJob.perform_async(Current.tenant_id, delivery.id)
      delivery
    end

    def self.normalize_recipient!(channel, value)
      recipient = value.to_s.strip
      valid = case channel
              when "email"
                URI::MailTo::EMAIL_REGEXP.match?(recipient)
              when "sms", "whatsapp"
                recipient.match?(/\A\+[1-9][0-9]{7,14}\z/)
              else
                false
              end
      raise InvalidDeliveryError, "recipient is invalid for #{channel}" unless valid

      channel == "email" ? recipient.downcase : recipient
    end
    private_class_method :normalize_recipient!
  end
end
