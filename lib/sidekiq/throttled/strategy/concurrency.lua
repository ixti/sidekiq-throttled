local key = KEYS[1]
local jid = ARGV[1]
local lmt = tonumber(ARGV[2])
local ttl = tonumber(ARGV[3])
local now = tonumber(ARGV[4])

redis.call("ZREMRANGEBYSCORE", key, "-inf", "(" .. now)

if lmt <= redis.call("ZCARD", key) and not redis.call("ZSCORE", key, jid) then
  return 1
end

redis.call("ZADD", key, now + ttl, jid)
redis.call("EXPIRE", key, ttl)

return 0
