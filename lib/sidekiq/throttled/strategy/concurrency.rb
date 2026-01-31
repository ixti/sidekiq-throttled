# frozen_string_literal: true

require "redis_prescription"

require_relative "./base"

module Sidekiq
  module Throttled
    class Strategy
      # Concurrency throttling strategy
      class Concurrency
        include Base

        # LUA script used to limit fetch concurrency.
        # Logic behind the scene can be described in following pseudo code:
        #
        #     if @limit <= LLEN(@key)
        #       return 1
        #     else
        #       PUSH(@key, @jid)
        #       return 0
        #     end
        SCRIPT = RedisPrescription.new(File.read("#{__dir__}/concurrency.lua"))
        private_constant :SCRIPT

        # @param [#to_s] strategy_key
        # @param [#to_i, #call] limit Amount of allowed concurrent jobs
        #   per processors running for given key.
        # @param [#to_i] avg_job_duration Average number of seconds needed
        #   to complete a job of this type. Default: 300 or 1/3 of lost_job_threshold
        # @param [#to_i] lost_job_threshold Seconds to wait before considering
        #   a job lost or dead. Default: 900 or 3 * avg_job_duration
        # @param [Proc] key_suffix Dynamic key suffix generator.
        # @param [#to_i] max_delay Maximum number of seconds to delay a job when it
        #   throttled. This prevents jobs from being schedule very far in the future
        #   when the backlog is large. Default: the smaller of 30 minutes or 10 * avg_job_duration
        # @deprecated @param [#to_i] ttl Obsolete alias for `lost_job_threshold`.
        #   Default: 900 or 3 * avg_job_duration
        def initialize(strategy_key, limit:, avg_job_duration: nil, ttl: nil, # rubocop:disable Metrics/ParameterLists
                       lost_job_threshold: ttl, key_suffix: nil, max_delay: nil)
          @base_key = "#{strategy_key}:concurrency.v2"
          @limit = limit
          @avg_job_duration, @lost_job_threshold = interp_duration_args(avg_job_duration, lost_job_threshold)
          @key_suffix = key_suffix
          @max_delay = max_delay || [(10 * @avg_job_duration), 1_800].min

          raise(ArgumentError, "lost_job_threshold must be greater than avg_job_duration") if
            @lost_job_threshold <= @avg_job_duration
        end

        # @return [Boolean] Whenever strategy has dynamic config
        def dynamic?
          @key_suffix || @limit.respond_to?(:call)
        end

        # @return [Boolean] whenever job is throttled or not
        def throttled?(jid, *job_args)
          job_limit = limit(job_args)
          return false unless job_limit
          return true if job_limit <= 0

          keys = [key(job_args), backlog_info_key(job_args)]
          argv = [jid.to_s, job_limit, @lost_job_threshold, Time.now.to_f]

          Sidekiq.redis { |redis| 1 == SCRIPT.call(redis, keys: keys, argv: argv) }
        end

        # @return [Float] How long, in seconds, before we'll next be able to take on jobs
        def retry_in(_jid, *job_args)
          job_limit = limit(job_args)
          return 0.0 if !job_limit || count(*job_args) < job_limit

          (estimated_backlog_size(job_args) * @avg_job_duration / limit(job_args))
            .then { |delay_sec| @max_delay * (1 - Math.exp(-delay_sec / @max_delay)) } # limit to max_delay
        end

        # @return [Integer] Current count of jobs
        def count(*job_args)
          Sidekiq.redis { |conn| conn.zcard(key(job_args)) }.to_i
        end

        # Resets count of jobs
        # @return [void]
        def reset!(*job_args)
          Sidekiq.redis { |conn| conn.del(key(job_args)) }
        end

        # Remove jid from the pool of jobs in progress
        # @return [void]
        def finalize!(jid, *job_args)
          Sidekiq.redis do |conn|
            conn.zrem(key(job_args), jid.to_s)
          end
        end

        def multi_strategy_payload(jid, job_args, now, job_limit)
          {
            type: "concurrency",
            jid: jid.to_s,
            limit: job_limit,
            lost_job_threshold: @lost_job_threshold,
            now: now
          }
        end

        def multi_strategy_keys(job_args)
          [key(job_args), backlog_info_key(job_args)]
        end

        private

        def backlog_info_key(job_args)
          "#{key(job_args)}.backlog_info"
        end

        def estimated_backlog_size(job_args)
          old_size_str, old_timestamp_str =
            Sidekiq.redis { |conn| conn.hmget(backlog_info_key(job_args), "size", "timestamp") }
          old_size = (old_size_str || 0).to_f
          old_timestamp = (old_timestamp_str || Time.now).to_f

          (old_size - jobs_lost_since(old_timestamp, job_args)).clamp(0, Float::INFINITY)
        end

        def jobs_lost_since(timestamp, job_args)
          (Time.now.to_f - timestamp) / @lost_job_threshold * limit(job_args)
        end

        def interp_duration_args(avg_job_duration, lost_job_threshold)
          if avg_job_duration && lost_job_threshold
            [avg_job_duration.to_i, lost_job_threshold.to_i]
          elsif avg_job_duration && lost_job_threshold.nil?
            [avg_job_duration.to_i, avg_job_duration.to_i * 3]
          elsif avg_job_duration.nil? && lost_job_threshold
            [lost_job_threshold.to_i / 3, lost_job_threshold.to_i]
          else
            [300, 900]
          end
        end
      end
    end
  end
end
