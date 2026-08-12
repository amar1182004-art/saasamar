CRYSTELL_REDIS_POOL = ConnectionPool.new(
  size: ENV.fetch("REDIS_POOL_SIZE", "10").to_i,
  timeout: ENV.fetch("REDIS_POOL_TIMEOUT", "1").to_f
) do
  Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/0"))
end
