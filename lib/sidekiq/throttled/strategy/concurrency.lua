local r, k, l, t, j = redis, KEYS[1], tonumber(ARGV[1]), tonumber(ARGV[2]), ARGV[3]
if l <= r.call("SCARD", k) and 0 == r.call("SISMEMBER", k, j) then return 1 end
r.call("SADD", k, j); r.call("EXPIRE", k, t); return 0
