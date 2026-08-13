require "json"

module ControlPlane
  class ConfigurationPayload
    class InvalidPayloadError < StandardError; end

    SENSITIVE_KEY_PATTERN = /(secret|token|password|credential|authorization|cookie|otp|mfa|private[_-]?key|api[_-]?key)/i

    def self.validate!(value, max_bytes:)
      payload = value.respond_to?(:to_h) ? value.to_h.deep_stringify_keys : nil
      raise InvalidPayloadError, "configuration must be an object" unless payload.is_a?(Hash)

      sensitive_path = find_sensitive_path(payload)
      if sensitive_path
        raise InvalidPayloadError, "configuration cannot contain secret-like key: #{sensitive_path}"
      end

      raise InvalidPayloadError, "configuration is too large" if JSON.generate(payload).bytesize > max_bytes

      JSON.parse(JSON.generate(payload))
    rescue JSON::GeneratorError
      raise InvalidPayloadError, "configuration must contain JSON-compatible values"
    end

    def self.find_sensitive_path(value, prefix = nil)
      case value
      when Hash
        value.each do |key, nested|
          path = [prefix, key.to_s].compact.join(".")
          return path if key.to_s.match?(SENSITIVE_KEY_PATTERN)

          nested_path = find_sensitive_path(nested, path)
          return nested_path if nested_path
        end
      when Array
        value.each_with_index do |nested, index|
          nested_path = find_sensitive_path(nested, "#{prefix}[#{index}]")
          return nested_path if nested_path
        end
      end

      nil
    end
    private_class_method :find_sensitive_path
  end
end
