require "digest"
require "securerandom"

module Auth
  class MfaChallenge
    TTL_SECONDS = ENV.fetch("MFA_CHALLENGE_TTL_SECONDS", "300").to_i
    MAX_ATTEMPTS = ENV.fetch("MFA_CHALLENGE_MAX_ATTEMPTS", "5").to_i

    FAILURE_SCRIPT = <<~LUA.freeze
      if redis.call('EXISTS', KEYS[1]) == 0 then
        return -1
      end

      local attempts = redis.call('HINCRBY', KEYS[1], 'attempts', 1)
      if attempts >= tonumber(ARGV[1]) then
        redis.call('DEL', KEYS[1])
      end
      return attempts
    LUA

    Result = Data.define(:token, :expires_in)

    def self.issue(user_id:)
      token = SecureRandom.urlsafe_base64(48)
      key = redis_key(token)

      CRYSTELL_REDIS_POOL.with do |redis|
        redis.multi do |transaction|
          transaction.hset(key, "user_id", user_id.to_s, "attempts", "0")
          transaction.expire(key, TTL_SECONDS)
        end
      end

      Result.new(token: token, expires_in: TTL_SECONDS)
    end

    def self.user_id(token)
      return if token.blank?

      CRYSTELL_REDIS_POOL.with { |redis| redis.hget(redis_key(token), "user_id") }
    end

    def self.record_failure!(token)
      CRYSTELL_REDIS_POOL.with do |redis|
        redis.eval(
          FAILURE_SCRIPT,
          keys: [redis_key(token)],
          argv: [MAX_ATTEMPTS]
        )
      end
    end

    def self.consume!(token)
      CRYSTELL_REDIS_POOL.with { |redis| redis.del(redis_key(token)) }
    end

    def self.redis_key(token)
      "auth:mfa:challenge:#{Digest::SHA256.hexdigest(token.to_s)}"
    end
    private_class_method :redis_key
  end
end
