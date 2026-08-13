module ControlPlane
  class AuditLog
    Result = Data.define(:events, :has_more, :next_offset)

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100
    MAX_OFFSET = 10_000
    SENSITIVE_KEY_PATTERN = /(secret|token|password|credential|authorization|cookie|otp|mfa)/i

    def self.call(action: nil, actor_id: nil, target_type: nil, target_id: nil, limit: nil, offset: nil, request_id: nil, ip_address: nil)
      user = ControlPlaneCurrent.user
      Permission.require!(user, "audit.read")

      safe_limit = normalize_limit(limit)
      safe_offset = normalize_offset(offset)
      scope = ControlPlaneAuditEvent.includes(:control_plane_user).order(occurred_at: :desc, id: :desc)
      scope = scope.where(action: action.to_s.first(120)) if action.present?
      scope = scope.where(control_plane_user_id: actor_id.to_s) if actor_id.present?
      scope = scope.where(target_type: target_type.to_s.first(120)) if target_type.present?
      scope = scope.where(target_id: target_id.to_s.first(255)) if target_id.present?

      rows = scope.limit(safe_limit + 1).offset(safe_offset).to_a
      has_more = rows.length > safe_limit
      events = rows.first(safe_limit)

      AuditWriter.call(
        action: "control_plane.audit_log_viewed",
        request_id: request_id,
        ip_address: ip_address,
        metadata: {
          filters: {
            action: action.to_s.presence,
            actor_id: actor_id.to_s.presence,
            target_type: target_type.to_s.presence,
            target_id: target_id.to_s.presence
          }.compact,
          limit: safe_limit,
          offset: safe_offset
        }
      )

      Result.new(
        events: events,
        has_more: has_more,
        next_offset: has_more ? safe_offset + safe_limit : nil
      )
    end

    def self.sanitize_metadata(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), sanitized|
          sanitized[key.to_s] = key.to_s.match?(SENSITIVE_KEY_PATTERN) ? "[REDACTED]" : sanitize_metadata(nested)
        end
      when Array
        value.map { |nested| sanitize_metadata(nested) }
      when String
        value.first(2_000)
      when Numeric, TrueClass, FalseClass, NilClass
        value
      else
        value.to_s.first(2_000)
      end
    end

    def self.normalize_limit(value)
      parsed = Integer(value || DEFAULT_LIMIT)
      [[parsed, 1].max, MAX_LIMIT].min
    rescue ArgumentError, TypeError
      DEFAULT_LIMIT
    end
    private_class_method :normalize_limit

    def self.normalize_offset(value)
      parsed = Integer(value || 0)
      [[parsed, 0].max, MAX_OFFSET].min
    rescue ArgumentError, TypeError
      0
    end
    private_class_method :normalize_offset
  end
end
