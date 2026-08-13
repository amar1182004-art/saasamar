module Notifications
  class Dispatcher
    class InvalidDeliveryError < StandardError; end

    def self.call(delivery_id:, now: Time.current)
      raise InvalidDeliveryError, "tenant context is required" if Current.tenant_id.blank?
      delivery = NotificationDelivery.includes(:communication_provider_account).find(delivery_id)
      return delivery if delivery.status == "sent"

      delivery.with_lock do
        return delivery if delivery.status == "sent"

        delivery.update!(status: "sending", attempts: delivery.attempts + 1, last_error: nil)
      end
      account = delivery.communication_provider_account
      adapter = Communications::AdapterRegistry.build(account)
      recipient = Communications::CredentialVault.decrypt(delivery.recipient_ciphertext, purpose: "notification-recipient")
      payload = Communications::CredentialVault.decrypt(delivery.payload_ciphertext, purpose: "notification-payload", parse_json: true)
      result = adapter.deliver(
        channel: delivery.channel,
        recipient: recipient,
        subject: payload["subject"],
        body: payload.fetch("body"),
        idempotency_key: delivery.idempotency_key
      )
      raise InvalidDeliveryError, "provider did not confirm delivery" unless result.status == "sent"

      delivery.update!(
        status: "sent",
        provider_message_id: result.provider_message_id,
        sent_at: now,
        failed_at: nil,
        metadata: delivery.metadata.merge(result.metadata || {})
      )
      delivery
    rescue StandardError => error
      NotificationDelivery.where(id: delivery_id).where.not(status: "sent").update_all(
        status: "failed",
        failed_at: now,
        last_error: error.message.to_s.first(1_000),
        updated_at: now
      )
      raise
    end
  end
end
