require "openssl"

module Auth
  class LoginThrottle
    WINDOW_SECONDS = ENV.fetch("LOGIN_THROTTLE_WINDOW_SECONDS", "900").to_i
    PAIR_LIMIT = ENV.fetch("LOGIN_MAX_PAIR_ATTEMPTS", "8").to_i
    IP_LIMIT = ENV.fetch("LOGIN_MAX_IP_ATTEMPTS", "60").to_i

    INCREMENT_SCRIPT = <<~LUA.freeze
      local value = redis.call('INCR', KEYS[1])
      if value == 1 then
        redis.call('EXPIRE', KEYS[1], ARGV[1])
      end
      return value
    LUA

    def initialize(email:, ip_address:)
      @email = email.to_s.strip.downcase
      @ip_address = ip_address.to_s
    end

    def blocked?
      pair_count >= PAIR_LIMIT || ip_count >= IP_LIMIT
    end

    def record_failure!
      CRYSTELL_REDIS_POOL.with do |redis|
        increment_with_expiry(redis, pair_key)
        increment_with_expiry(redis, ip_key)
      end
    end

    def reset_success!
      CRYSTELL_REDIS_POOL.with { |redis| redis.del(pair_key) }
    end

    def retry_after
      CRYSTELL_REDIS_POOL.with do |redis|
        [redis.ttl(pair_key), redis.ttl(ip_key), 1].max
      end
    end

    private

    attr_reader :email, :ip_address

    def pair_count
      read_count(pair_key)
    end

    def ip_count
      read_count(ip_key)
    end

    def read_count(key)
      CRYSTELL_REDIS_POOL.with { |redis| redis.get(key).to_i }
    end

    def increment_with_expiry(redis, key)
      redis.eval(
        INCREMENT_SCRIPT,
        keys: [key],
        argv: [WINDOW_SECONDS]
      )
    end

    def pair_key
      "auth:login:pair:#{fingerprint("#{email}\0#{ip_address}")}"
    end

    def ip_key
      "auth:login:ip:#{fingerprint(ip_address)}"
    end

    def fingerprint(value)
      key = ENV.fetch("LOGIN_THROTTLE_KEY", ENV.fetch("SECRET_KEY_BASE"))
      OpenSSL::HMAC.hexdigest("SHA256", key, value)
    end
  end
end
