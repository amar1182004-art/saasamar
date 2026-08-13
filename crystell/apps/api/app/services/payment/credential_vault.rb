require "base64"
require "digest"
require "json"

module Payment
  class CredentialVault
    class ConfigurationError < StandardError; end
    class DecryptionError < StandardError; end

    KEY_BYTES = 32

    def self.encrypt(value, purpose:)
      payload = value.is_a?(String) ? value : JSON.generate(value)
      encryptor.encrypt_and_sign(payload, purpose: purpose.to_s)
    end

    def self.decrypt(ciphertext, purpose:, parse_json: false)
      value = encryptor.decrypt_and_verify(ciphertext, purpose: purpose.to_s)
      parse_json ? JSON.parse(value) : value
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, JSON::ParserError => error
      raise DecryptionError, error.message
    end

    def self.encryptor
      @encryptor ||= ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
    end
    private_class_method :encryptor

    def self.key
      encoded = ENV["PAYMENT_SECRETS_KEY"].to_s
      if encoded.present?
        decoded = Base64.strict_decode64(encoded)
        raise ConfigurationError, "PAYMENT_SECRETS_KEY must decode to 32 bytes" unless decoded.bytesize == KEY_BYTES

        return decoded
      end

      if Rails.env.production?
        raise ConfigurationError, "PAYMENT_SECRETS_KEY is required in production"
      end

      Digest::SHA256.digest("#{Rails.application.secret_key_base}:crystell:payment-secrets")
    rescue ArgumentError
      raise ConfigurationError, "PAYMENT_SECRETS_KEY must be strict base64"
    end
    private_class_method :key
  end
end
