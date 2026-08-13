require "digest"

module Payment
  class WebhookReceiver
    class ReplayConflictError < StandardError; end

    Result = Data.define(:event, :duplicate)

    def self.call(endpoint_id:, raw_body:, headers:, now: Time.current)
      resolution = Payment::WebhookEndpointResolver.call(endpoint_id: endpoint_id)

      TenantSystemAccess.with(tenant_id: resolution.tenant_id) do
        account = PaymentProviderAccount.active.find_by!(
          id: resolution.payment_provider_account_id,
          store_id: resolution.store_id
        )
        adapter = Payment::AdapterRegistry.build(account)
        signature = adapter.verify_webhook!(raw_body: raw_body, headers: headers)
        parsed = adapter.parse_webhook(raw_body: raw_body)

        payload_digest = Digest::SHA256.hexdigest(raw_body)
        signature_digest = Digest::SHA256.hexdigest(signature.to_s)
        event, duplicate = find_or_create_event!(
          account: account,
          parsed: parsed,
          raw_body: raw_body,
          payload_digest: payload_digest,
          signature_digest: signature_digest,
          now: now
        )

        unless %w[processed ignored].include?(event.status)
          begin
            Payment::WebhookEventProcessor.call(event: event, parsed: parsed, now: now)
          rescue StandardError
            # The event is deliberately kept with status=failed for inspection/retry.
          end
        end

        Result.new(event: event.reload, duplicate: duplicate)
      end
    end

    def self.find_or_create_event!(account:, parsed:, raw_body:, payload_digest:, signature_digest:, now:)
      existing = PaymentWebhookEvent.find_by(
        payment_provider_account_id: account.id,
        provider_event_id: parsed.provider_event_id
      )
      return [verify_replay!(existing, payload_digest), true] if existing

      created = nil
      begin
        ApplicationRecord.transaction(requires_new: true) do
          created = PaymentWebhookEvent.create!(
            tenant_id: Current.tenant_id,
            store_id: account.store_id,
            payment_provider_account_id: account.id,
            provider_event_id: parsed.provider_event_id,
            event_type: parsed.event_type,
            status: "received",
            payload_digest: payload_digest,
            signature_digest: signature_digest,
            raw_body: raw_body,
            received_at: now,
            metadata: {}
          )
        end
        [created, false]
      rescue ActiveRecord::RecordNotUnique
        existing = PaymentWebhookEvent.find_by!(
          payment_provider_account_id: account.id,
          provider_event_id: parsed.provider_event_id
        )
        [verify_replay!(existing, payload_digest), true]
      end
    end
    private_class_method :find_or_create_event!

    def self.verify_replay!(event, payload_digest)
      return event if event.payload_digest == payload_digest

      raise ReplayConflictError, "provider event id was replayed with a different payload"
    end
    private_class_method :verify_replay!
  end
end
