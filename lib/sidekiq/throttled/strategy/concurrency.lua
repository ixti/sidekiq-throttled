local key = KEYS[1]
local jid = ARGV[1]
local lmt = tonumber(ARGV[2])
local ttl = tonumber(ARGV[3])

if lmt <= redis.call("SCARD", key) and 0 == redis.call("SISMEMBER", key, jid) then
  return 1
end

redis.call("SADD", key, jid)
redis.call("EXPIRE", key, ttl)

return 0
