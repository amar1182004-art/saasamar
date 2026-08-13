module ControlPlane
  class FeatureFlagRegistry
    class InvalidFlagError < StandardError; end
    class ElevationRequiredError < StandardError; end

    MAX_CONFIG_BYTES = 32_768
    KEY_PATTERN = /\A[a-z0-9][a-z0-9._-]{0,119}\z/

    def self.list
      Permission.require!(ControlPlaneCurrent.user, "feature_flags.read")
      ControlPlaneFeatureFlag.order(:key).limit(500).to_a
    end

    def self.read(key:)
      Permission.require!(ControlPlaneCurrent.user, "feature_flags.read")
      ControlPlaneFeatureFlag.find_by!(key: normalize_key!(key))
    end

    def self.upsert(key:, description: nil, enabled: nil, rollout_percentage: nil, config: nil, reason:, request_id: nil, ip_address: nil)
      Permission.require!(ControlPlaneCurrent.user, "feature_flags.manage")
      require_elevated!
      normalized_key = normalize_key!(key)
      normalized_reason = normalize_reason!(reason)
      result = nil

      ControlPlaneRecord.transaction do
        record = ControlPlaneFeatureFlag.create_or_find_by!(key: normalized_key)
        record.lock!
        attributes = {}
        attributes[:description] = normalize_description(description) unless description.nil?
        attributes[:enabled] = normalize_boolean!(enabled) unless enabled.nil?
        attributes[:rollout_percentage] = normalize_rollout!(rollout_percentage) unless rollout_percentage.nil?
        attributes[:config] = normalize_config!(config) unless config.nil?
        record.update!(attributes) unless attributes.empty?

        AuditWriter.call(
          action: "control_plane.feature_flag_updated",
          target_type: "ControlPlaneFeatureFlag",
          target_id: record.id,
          request_id: request_id,
          ip_address: ip_address,
          reason: normalized_reason,
          metadata: {
            key: record.key,
            enabled: record.enabled,
            rollout_percentage: record.rollout_percentage,
            changed_fields: attributes.keys.map(&:to_s).sort
          }
        )
        result = record
      end

      result
    rescue ConfigurationPayload::InvalidPayloadError => error
      raise InvalidFlagError, error.message
    end

    def self.normalize_key!(key)
      value = key.to_s
      raise InvalidFlagError, "feature flag key is invalid" unless KEY_PATTERN.match?(value)

      value
    end
    private_class_method :normalize_key!

    def self.normalize_reason!(reason)
      value = reason.to_s.strip
      raise InvalidFlagError, "reason must be between 3 and 500 characters" unless value.length.between?(3, 500)

      value
    end
    private_class_method :normalize_reason!

    def self.normalize_description(value)
      text = value.to_s.strip
      raise InvalidFlagError, "description is too long" if text.length > 1_000

      text.presence
    end
    private_class_method :normalize_description

    def self.normalize_boolean!(value)
      return value if value == true || value == false

      raise InvalidFlagError, "enabled must be a boolean"
    end
    private_class_method :normalize_boolean!

    def self.normalize_rollout!(value)
      parsed = Integer(value)
      raise InvalidFlagError, "rollout percentage must be between 0 and 100" unless parsed.between?(0, 100)

      parsed
    rescue ArgumentError, TypeError
      raise InvalidFlagError, "rollout percentage must be between 0 and 100"
    end
    private_class_method :normalize_rollout!

    def self.normalize_config!(config)
      ConfigurationPayload.validate!(config, max_bytes: MAX_CONFIG_BYTES)
    end
    private_class_method :normalize_config!

    def self.require_elevated!
      raise ElevationRequiredError, "privilege elevation is required" unless ControlPlaneCurrent.session&.elevated?
    end
    private_class_method :require_elevated!
  end
end
