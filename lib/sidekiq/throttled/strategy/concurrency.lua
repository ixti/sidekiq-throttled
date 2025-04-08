local in_progress_jobs_key = KEYS[1]
local backlog_info_key = KEYS[2]
local jid = ARGV[1]
local lmt = tonumber(ARGV[2])
local lost_job_threshold = tonumber(ARGV[3])
local now = tonumber(ARGV[4])

-- supporting functions
local function over_limit()
  return lmt <= redis.call("ZCARD", in_progress_jobs_key)
end

local function job_already_in_progress()
  return redis.call("ZSCORE", in_progress_jobs_key, jid)
end

-- Estimates current backlog size. This function tends to underestimate 
-- the actual backlog. This is intentional. Overestimates are bad as it
-- can cause unnecessary delays in job processing. Underestimates are much
-- safer as they only increase workload of sidekiq processors. 
local function est_current_backlog_size()
  local old_size = tonumber(redis.call("HGET", backlog_info_key, "size") or 0)
  local old_timestamp = tonumber(redis.call("HGET", backlog_info_key, "timestamp") or now)
  
  local jobs_lost_since_old_timestamp = (now - old_timestamp) / lost_job_threshold * lmt

  return math.max(old_size - jobs_lost_since_old_timestamp, 0) 
end


local function change_backlog_size(delta)
  local curr_backlog_size = est_current_backlog_size()

  redis.call("HSET", backlog_info_key, "size", curr_backlog_size + delta) 
  redis.call("HSET", backlog_info_key, "timestamp", now)
  redis.call("EXPIRE", backlog_info_key, math.ceil((lost_job_threshold * curr_backlog_size) + 1 / lmt))
end

local function register_job_in_progress()
  redis.call("ZADD", in_progress_jobs_key, now + lost_job_threshold , jid)
  redis.call("EXPIRE", in_progress_jobs_key, lost_job_threshold)
end

local function clear_stale_in_progress_jobs()
  local cleared_count = redis.call("ZREMRANGEBYSCORE", in_progress_jobs_key, "-inf", "(" .. now)
  change_backlog_size(-cleared_count)
end

-- END supporting functions

clear_stale_in_progress_jobs()

if over_limit() and not job_already_in_progress() then
  change_backlog_size(1)
  return 1
end

register_job_in_progress()
change_backlog_size(-1)

return 0
