local key = KEYS[1]
local jid = KEYS[2]
local lmt = tonumber(ARGV[1])
local ttl = tonumber(ARGV[2])

if lmt <= redis.call("SCARD", key) and 0 == redis.call("SISMEMBER", key, jid) then
  return 1
end

redis.call("SADD", key, jid)
redis.call("EXPIRE", key, ttl)

return 0
