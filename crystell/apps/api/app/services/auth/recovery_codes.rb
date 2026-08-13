require "openssl"
require "securerandom"

module Auth
  class RecoveryCodes
    COUNT = 10

    def self.generate
      Array.new(COUNT) { SecureRandom.hex(8) }
    end

    def self.digest(code)
      key = ENV.fetch("MFA_RECOVERY_PEPPER", ENV.fetch("SECRET_KEY_BASE"))
      OpenSSL::HMAC.hexdigest("SHA256", key, code.to_s.strip.downcase)
    end

    def self.digests(codes)
      codes.map { |code| digest(code) }
    end
  end
end
