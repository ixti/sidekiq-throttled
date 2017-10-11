local key = KEYS[1]
local jid = KEYS[2]
local lmt = tonumber(ARGV[1])
local ttl = tonumber(ARGV[2])
local now = tonumber(ARGV[3])

redis.call("ZREMRANGEBYSCORE", key, "-inf", "(" .. now)

if lmt <= redis.call("ZCARD", key) and not redis.call("ZSCORE", key, jid) then
  return 1
end

redis.call("ZADD", key, now + ttl, jid)
redis.call("EXPIRE", key, ttl)

return 0
