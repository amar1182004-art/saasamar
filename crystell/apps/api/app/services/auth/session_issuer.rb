require "digest"
require "openssl"
require "securerandom"

module Auth
  class SessionIssuer
    Result = Data.define(:token, :session_id, :expires_at)

    def self.call(user_id:, ip_address: nil, user_agent: nil)
      token = SecureRandom.urlsafe_base64(48)
      token_digest = Digest::SHA256.hexdigest(token)
      expires_at = ENV.fetch("SESSION_TTL_HOURS", "168").to_i.hours.from_now

      session = IdentityScope.with(user_id) do
        Session.create!(
          user_id: user_id,
          token_digest: token_digest,
          expires_at: expires_at,
          ip_hash: hash_ip(ip_address),
          user_agent: user_agent.to_s.first(512).presence
        )
      end

      Result.new(token: token, session_id: session.id, expires_at: expires_at)
    end

    def self.hash_ip(ip_address)
      return if ip_address.blank?

      key = ENV.fetch("SESSION_METADATA_KEY", ENV.fetch("SECRET_KEY_BASE"))
      OpenSSL::HMAC.hexdigest("SHA256", key, ip_address.to_s)
    end
    private_class_method :hash_ip
  end
end
