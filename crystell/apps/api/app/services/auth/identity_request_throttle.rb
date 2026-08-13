require "openssl"

module Auth
  class IdentityRequestThrottle
    WINDOW_SECONDS = ENV.fetch("IDENTITY_REQUEST_WINDOW_SECONDS", "3600").to_i
    PAIR_LIMIT = ENV.fetch("IDENTITY_MAX_PAIR_REQUESTS", "5").to_i
    IP_LIMIT = ENV.fetch("IDENTITY_MAX_IP_REQUESTS", "30").to_i

    INCREMENT_SCRIPT = <<~LUA.freeze
      local value = redis.call('INCR', KEYS[1])
      if value == 1 then
        redis.call('EXPIRE', KEYS[1], ARGV[1])
      end
      return value
    LUA

    def initialize(email:, ip_address:, purpose:)
      @email = email.to_s.strip.downcase
      @ip_address = ip_address.to_s
      @purpose = purpose.to_s
    end

    def blocked?
      pair_count >= PAIR_LIMIT || ip_count >= IP_LIMIT
    end

    def record!
      CRYSTELL_REDIS_POOL.with do |redis|
        increment(redis, pair_key)
        increment(redis, ip_key)
      end
    end

    def retry_after
      CRYSTELL_REDIS_POOL.with do |redis|
        [redis.ttl(pair_key), redis.ttl(ip_key), 1].max
      end
    end

    private

    attr_reader :email, :ip_address, :purpose

    def pair_count
      read_count(pair_key)
    end

    def ip_count
      read_count(ip_key)
    end

    def read_count(key)
      CRYSTELL_REDIS_POOL.with { |redis| redis.get(key).to_i }
    end

    def increment(redis, key)
      redis.eval(INCREMENT_SCRIPT, keys: [key], argv: [WINDOW_SECONDS])
    end

    def pair_key
      "auth:identity-request:pair:#{fingerprint("#{purpose}\0#{email}\0#{ip_address}")}"
    end

    def ip_key
      "auth:identity-request:ip:#{fingerprint("#{purpose}\0#{ip_address}")}"
    end

    def fingerprint(value)
      key = ENV.fetch("IDENTITY_REQUEST_THROTTLE_KEY", ENV.fetch("SECRET_KEY_BASE"))
      OpenSSL::HMAC.hexdigest("SHA256", key, value)
    end
  end
end
