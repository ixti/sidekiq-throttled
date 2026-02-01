-- Expects ARGV[1] to be a JSON array of strategy hashes.
-- Each strategy hash must include:
--   * type: "concurrency" or "threshold"
--   * For concurrency: jid, limit, lost_job_threshold, now
--   * For threshold: limit, period, now
-- KEYS must include the Redis keys for each strategy in order:
--   * concurrency: [in_progress_jobs_key, backlog_info_key]
--   * threshold: [key]
-- Returns: { any_throttled (1/0), per_strategy_throttled... }

local strategies = cjson.decode(ARGV[1])
local key_index = 1

local function est_current_backlog_size(backlog_info_key, lost_job_threshold, lmt, now)
  local old_size = tonumber(redis.call("HGET", backlog_info_key, "size")) or 0
  local old_timestamp = tonumber(redis.call("HGET", backlog_info_key, "timestamp")) or now

  if not lost_job_threshold or lost_job_threshold <= 0 or not lmt or lmt <= 0 then
    return math.max(old_size, 0)
  end

  local jobs_lost_since_old_timestamp = (now - old_timestamp) / lost_job_threshold * lmt
  return math.max(old_size - jobs_lost_since_old_timestamp, 0)
end

local function set_backlog_state(backlog_info_key, size, now, lost_job_threshold, lmt)
  local safe_size = math.max(size, 0)

  redis.call("HSET", backlog_info_key, "size", safe_size)
  redis.call("HSET", backlog_info_key, "timestamp", now)

  if lost_job_threshold and lost_job_threshold > 0 and lmt and lmt > 0 then
    local ttl = math.ceil((lost_job_threshold * safe_size) + (1 / lmt))
    if ttl < 1 then ttl = 1 end
    redis.call("EXPIRE", backlog_info_key, ttl)
  else
    redis.call("EXPIRE", backlog_info_key, 1)
  end
end

local function change_backlog_size(backlog_info_key, lost_job_threshold, lmt, now, delta)
  local curr = est_current_backlog_size(backlog_info_key, lost_job_threshold, lmt, now)
  set_backlog_state(backlog_info_key, curr + delta, now, lost_job_threshold, lmt)
end

local function register_job_in_progress(in_progress_jobs_key, lost_job_threshold, jid, now)
  -- Keep the sorted set itself from living forever; per-member TTL is via score.
  redis.call("ZADD", in_progress_jobs_key, now + lost_job_threshold, jid)
  redis.call("EXPIRE", in_progress_jobs_key, lost_job_threshold)
end

local function clear_stale_in_progress_jobs(in_progress_jobs_key, backlog_info_key, lost_job_threshold, lmt, now)
  -- Maintenance: we must be able to clear stale entries even if job is throttled,
  -- otherwise stale locks can deadlock the system forever.
  local cleared_count = redis.call("ZREMRANGEBYSCORE", in_progress_jobs_key, "-inf", "(" .. now)
  if cleared_count and tonumber(cleared_count) and tonumber(cleared_count) > 0 then
    change_backlog_size(backlog_info_key, lost_job_threshold, lmt, now, -tonumber(cleared_count))
  end
end

local strategy_states = {}
local results = {}
local any_throttled = false

-- Phase 1: evaluate throttling (only safe maintenance writes allowed)
for i = 1, #strategies do
  local strategy = strategies[i]
  local strategy_type = strategy["type"]
  local state = { type = strategy_type }

  if strategy_type == "concurrency" then
    local in_progress_jobs_key = KEYS[key_index]
    local backlog_info_key = KEYS[key_index + 1]
    key_index = key_index + 2

    local jid = tostring(strategy["jid"])
    local lmt = tonumber(strategy["limit"])
    local lost_job_threshold = tonumber(strategy["lost_job_threshold"])
    local now = tonumber(strategy["now"])

    state.in_progress_jobs_key = in_progress_jobs_key
    state.backlog_info_key = backlog_info_key
    state.jid = jid
    state.lmt = lmt
    state.lost_job_threshold = lost_job_threshold
    state.now = now

    -- Maintenance
    clear_stale_in_progress_jobs(in_progress_jobs_key, backlog_info_key, lost_job_threshold, lmt, now)

    local job_already_in_progress = redis.call("ZSCORE", in_progress_jobs_key, jid)
    local throttled = false
    local over_limit = false

    if not lmt then
      throttled = false
    elseif lmt <= 0 then
      -- limit <= 0 means "no capacity"; let already-running jobs continue
      throttled = (job_already_in_progress == false or job_already_in_progress == nil)
      over_limit = true
    else
      over_limit = (lmt <= redis.call("ZCARD", in_progress_jobs_key))
      if over_limit and (job_already_in_progress == false or job_already_in_progress == nil) then
        throttled = true
      end
    end

    state.over_limit = over_limit
    state.job_already_in_progress = job_already_in_progress
    state.throttled = throttled
    results[i] = throttled and 1 or 0

  elseif strategy_type == "threshold" then
    local key = KEYS[key_index]
    key_index = key_index + 1

    local lmt = tonumber(strategy["limit"])
    local ttl = tonumber(strategy["period"])
    local now = tonumber(strategy["now"])

    state.key = key
    state.lmt = lmt
    state.ttl = ttl
    state.now = now

    local throttled = false

    if not lmt then
      throttled = false
    elseif lmt <= 0 then
      throttled = true
    else
      local llen = redis.call("LLEN", key)
      if lmt <= llen then
        local oldest = redis.call("LINDEX", key, -1)
        local oldest_ts = tonumber(oldest)

        if oldest_ts and ttl and ttl > 0 then
          if (now - oldest_ts) < ttl then
            throttled = true
          end
        end
      end
    end

    state.throttled = throttled
    results[i] = throttled and 1 or 0
  else
    error("Unknown strategy type: " .. tostring(strategy_type))
  end

  if state.throttled then
    any_throttled = true
  end

  strategy_states[i] = state
end

-- Phase 2: commit mutations ONLY if admitted (no throttling)
if any_throttled then
  -- If throttled, we do NOT register concurrency, do NOT decrement backlog,
  -- and do NOT increment threshold counters.
  --
  -- We also do NOT bump backlog size here; backlog should represent actual admitted backlog,
  -- and increasing it while throttled can explode scheduling delays.
  --
  -- (Stale cleanup already happened above.)
else
  for i = 1, #strategy_states do
    local state = strategy_states[i]

    if state.type == "concurrency" then
      -- Admit job into concurrency set
      register_job_in_progress(state.in_progress_jobs_key, state.lost_job_threshold, state.jid, state.now)

      -- If you model backlog size as "queued-but-not-admitted", decrement on admit
      change_backlog_size(state.backlog_info_key, state.lost_job_threshold, state.lmt, state.now, -1)

    elseif state.type == "threshold" then
      redis.call("LPUSH", state.key, state.now)
      redis.call("LTRIM", state.key, 0, state.lmt - 1)
      redis.call("EXPIRE", state.key, state.ttl)
    end
  end
end

return { any_throttled and 1 or 0, unpack(results) }
