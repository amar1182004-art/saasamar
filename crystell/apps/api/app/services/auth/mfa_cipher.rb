require "digest"

module Auth
  class MfaCipher
    VERSION = "v1"

    def self.encrypt(plaintext)
      "#{VERSION}:#{encryptor.encrypt_and_sign(plaintext.to_s)}"
    end

    def self.decrypt(ciphertext)
      version, payload = ciphertext.to_s.split(":", 2)
      raise ActiveSupport::MessageEncryptor::InvalidMessage unless version == VERSION && payload.present?

      encryptor.decrypt_and_verify(payload)
    end

    def self.encryptor
      @encryptor ||= begin
        raw_key = ENV.fetch("MFA_ENCRYPTION_KEY")
        key = Digest::SHA256.digest(raw_key)
        ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
      end
    end
    private_class_method :encryptor
  end
end
