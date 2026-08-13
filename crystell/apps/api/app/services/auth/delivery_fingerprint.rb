require "openssl"

module Auth
  class DeliveryFingerprint
    def self.call(destination)
      normalized = destination.to_s.strip.downcase
      key = ENV.fetch("IDENTITY_DELIVERY_FINGERPRINT_KEY", ENV.fetch("SECRET_KEY_BASE"))
      OpenSSL::HMAC.hexdigest("SHA256", key, normalized)
    end
  end
end
