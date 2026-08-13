require "digest"

module Communications
  module Adapters
    class Reference < Base
      def deliver(channel:, recipient:, subject:, body:, idempotency_key:)
        raise ArgumentError, "channel does not match the provider account" unless channel.to_s == account.channel
        raise ArgumentError, "recipient is required" if recipient.blank?
        raise ArgumentError, "message body is required" if body.blank?

        digest = Digest::SHA256.hexdigest("#{account.id}:#{idempotency_key}").first(24)
        Result.new(
          provider_message_id: "reference-#{channel}-#{digest}",
          status: "sent",
          metadata: { "mode" => account.mode, "subject_present" => subject.present? }
        )
      end
    end
  end
end
