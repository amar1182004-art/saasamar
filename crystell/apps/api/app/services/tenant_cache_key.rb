class TenantCacheKey
  class InvalidKeyError < StandardError; end

  SAFE_SEGMENT = /\A[a-zA-Z0-9._-]+\z/

  def self.build(tenant_id:, namespace:, *parts)
    tenant = segment!(tenant_id, "tenant_id")
    scope = segment!(namespace, "namespace")
    values = parts.map.with_index { |part, index| segment!(part, "part_#{index}") }

    (["tenant", tenant, scope] + values).join(":")
  end

  def self.segment!(value, name)
    segment = value.to_s
    raise InvalidKeyError, "#{name} is required" if segment.blank?
    raise InvalidKeyError, "#{name} contains unsafe characters" unless segment.match?(SAFE_SEGMENT)

    segment
  end
  private_class_method :segment!
end
