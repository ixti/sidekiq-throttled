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

  local jobs_lost_since_old_timestamp = (now - old_timestamp) / lost_job_threshold * lmt

  return math.max(old_size - jobs_lost_since_old_timestamp, 0)
end

local function change_backlog_size(backlog_info_key, lost_job_threshold, lmt, now, delta)
  local curr_backlog_size = est_current_backlog_size(backlog_info_key, lost_job_threshold, lmt, now)

  redis.call("HSET", backlog_info_key, "size", curr_backlog_size + delta)
  redis.call("HSET", backlog_info_key, "timestamp", now)
  redis.call("EXPIRE", backlog_info_key, math.ceil((lost_job_threshold * curr_backlog_size) + 1 / lmt))
end

local function register_job_in_progress(in_progress_jobs_key, lost_job_threshold, jid, now)
  redis.call("ZADD", in_progress_jobs_key, now + lost_job_threshold, jid)
  redis.call("EXPIRE", in_progress_jobs_key, lost_job_threshold)
end

local function clear_stale_in_progress_jobs(in_progress_jobs_key, backlog_info_key, lost_job_threshold, lmt, now)
  local cleared_count = redis.call("ZREMRANGEBYSCORE", in_progress_jobs_key, "-inf", "(" .. now)
  change_backlog_size(backlog_info_key, lost_job_threshold, lmt, now, -cleared_count)
end

local strategy_states = {}
local results = {}
local any_throttled = false

for i = 1, #strategies do
  local strategy = strategies[i]
  local strategy_type = strategy["type"]
  local state = { type = strategy_type }

  if strategy_type == "concurrency" then
    local in_progress_jobs_key = KEYS[key_index]
    local backlog_info_key = KEYS[key_index + 1]
    key_index = key_index + 2

    local jid = strategy["jid"]
    local lmt = tonumber(strategy["limit"])
    local lost_job_threshold = tonumber(strategy["lost_job_threshold"])
    local now = tonumber(strategy["now"])

    state.in_progress_jobs_key = in_progress_jobs_key
    state.backlog_info_key = backlog_info_key
    state.jid = jid
    state.lmt = lmt
    state.lost_job_threshold = lost_job_threshold
    state.now = now

    local throttled = false
    local job_already_in_progress = redis.call("ZSCORE", in_progress_jobs_key, jid)
    local over_limit = false

    if lmt <= 0 then
      throttled = true
    else
      clear_stale_in_progress_jobs(in_progress_jobs_key, backlog_info_key, lost_job_threshold, lmt, now)
      over_limit = lmt <= redis.call("ZCARD", in_progress_jobs_key)
      if over_limit and not job_already_in_progress then
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
    if lmt <= 0 then
      throttled = true
    elseif lmt <= redis.call("LLEN", key) and now - redis.call("LINDEX", key, -1) < ttl then
      throttled = true
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

if any_throttled then
  for i = 1, #strategy_states do
    local state = strategy_states[i]
    if state.type == "concurrency" and state.throttled then
      if state.lmt > 0 and state.over_limit and not state.job_already_in_progress then
        change_backlog_size(state.backlog_info_key, state.lost_job_threshold, state.lmt, state.now, 1)
      end
    end
  end
else
  for i = 1, #strategy_states do
    local state = strategy_states[i]
    if state.type == "concurrency" then
      if state.lmt > 0 then
        register_job_in_progress(state.in_progress_jobs_key, state.lost_job_threshold, state.jid, state.now)
        change_backlog_size(state.backlog_info_key, state.lost_job_threshold, state.lmt, state.now, -1)
      end
    elseif state.type == "threshold" then
      redis.call("LPUSH", state.key, state.now)
      redis.call("LTRIM", state.key, 0, state.lmt - 1)
      redis.call("EXPIRE", state.key, state.ttl)
    end
  end
end

return { any_throttled and 1 or 0, unpack(results) }
