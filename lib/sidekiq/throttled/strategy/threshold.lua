local key = KEYS[1]
local lmt = tonumber(ARGV[1])
local ttl = tonumber(ARGV[2])
local now = tonumber(ARGV[3])

if lmt <= redis.call("LLEN", key) and now - redis.call("LINDEX", key, -1) < ttl then
  return 1
end

redis.call("LPUSH", key, now)
redis.call("LTRIM", key, 0, lmt - 1)
redis.call("EXPIRE", key, ttl)

return 0
