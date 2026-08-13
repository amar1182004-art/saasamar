class TenantJobEnvelope
  class InvalidEnvelopeError < StandardError; end

  VERSION = 1
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  def self.build(tenant_id:, payload:, store_id: nil, actor_user_id: nil)
    {
      "version" => VERSION,
      "tenant_id" => uuid!(tenant_id, "tenant_id"),
      "store_id" => optional_uuid!(store_id, "store_id"),
      "actor_user_id" => optional_uuid!(actor_user_id, "actor_user_id"),
      "payload" => payload.deep_stringify_keys
    }.compact
  end

  def self.validate!(envelope)
    data = envelope.to_h.deep_stringify_keys
    raise InvalidEnvelopeError, "unsupported envelope version" unless data["version"] == VERSION

    uuid!(data["tenant_id"], "tenant_id")
    optional_uuid!(data["store_id"], "store_id")
    optional_uuid!(data["actor_user_id"], "actor_user_id")
    raise InvalidEnvelopeError, "payload must be an object" unless data["payload"].is_a?(Hash)

    data
  end

  def self.uuid!(value, name)
    normalized = value.to_s
    raise InvalidEnvelopeError, "#{name} is required" unless normalized.match?(UUID_PATTERN)

    normalized
  end
  private_class_method :uuid!

  def self.optional_uuid!(value, name)
    return if value.blank?

    uuid!(value, name)
  end
  private_class_method :optional_uuid!
end
