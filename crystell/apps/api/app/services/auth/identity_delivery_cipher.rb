require "digest"

module Auth
  class IdentityDeliveryCipher
    VERSION = "v1"

    def self.encrypt(payload)
      "#{VERSION}:#{encryptor.encrypt_and_sign(payload.to_json)}"
    end

    def self.decrypt(ciphertext)
      version, payload = ciphertext.to_s.split(":", 2)
      raise ActiveSupport::MessageEncryptor::InvalidMessage unless version == VERSION && payload.present?

      JSON.parse(encryptor.decrypt_and_verify(payload))
    end

    def self.encryptor
      @encryptor ||= begin
        raw_key = ENV.fetch("IDENTITY_DELIVERY_ENCRYPTION_KEY")
        key = Digest::SHA256.digest(raw_key)
        ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
      end
    end
    private_class_method :encryptor
  end
end
