local r, k, l, p, t = redis, KEYS[1], tonumber(ARGV[1]), tonumber(ARGV[2]), tonumber(ARGV[3])
if l <= r.call("LLEN", k) and t - r.call("LINDEX", k, -1) < p then return 1 end
r.call("LPUSH", k, t); r.call("LTRIM", k, 0, l - 1); r.call("EXPIRE", k, p); return 0
