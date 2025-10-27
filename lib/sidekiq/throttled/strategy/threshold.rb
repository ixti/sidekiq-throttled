# frozen_string_literal: true

require "redis_prescription"

require_relative "./base"

module Sidekiq
  module Throttled
    class Strategy
      # Threshold throttling strategy
      # @todo Use redis TIME command instead of sending current timestamp from
      #   sidekiq manager. See: http://redis.io/commands/time
      class Threshold
        include Base

        # LUA script used to limit fetch threshold.
        # Logic behind the scene can be described in following pseudo code:
        #
        #     def exceeded?
        #       limit <= LLEN(@key) && NOW - LINDEX(@key, -1) < @period
        #     end
        #
        #     def increase!
        #       LPUSH(@key, NOW)
        #       LTRIM(@key, 0, @limit - 1)
        #       EXPIRE(@key, @period)
        #     end
        #
        #     return 1 if exceeded?
        #
        #     increase!
        #     return 0
        SCRIPT = RedisPrescription.new(File.read("#{__dir__}/threshold.lua"))
        private_constant :SCRIPT

        # @param [#to_s] strategy_key
        # @param [#to_i, #call] limit Amount of allowed concurrent jobs
        #   per period running for given key.
        # @param [#to_f, #call] :period Period in seconds.
        # @param [Proc] key_suffix Dynamic key suffix generator.
        def initialize(strategy_key, limit:, period:, key_suffix: nil)
          @base_key   = "#{strategy_key}:threshold"
          @limit      = limit
          @period     = period
          @key_suffix = key_suffix
        end

        # @return [Float] Period in seconds
        def period(job_args = nil)
          return @period.to_f unless @period.respond_to? :call

          @period.call(*job_args).to_f
        end

        # @return [Boolean] Whenever strategy has dynamic config
        def dynamic?
          @key_suffix || @limit.respond_to?(:call) || @period.respond_to?(:call)
        end

        # @return [Boolean] whenever job is throttled or not
        def throttled?(*job_args)
          job_limit = limit(job_args)
          return false unless job_limit
          return true if job_limit <= 0

          keys = [key(job_args)]
          argv = [job_limit, period(job_args), Time.now.to_f]

          Sidekiq.redis { |redis| 1 == SCRIPT.call(redis, keys: keys, argv: argv) }
        end

        # @return [Float] How long, in seconds, before we'll next be able to take on jobs
        def retry_in(*job_args)
          job_limit = limit(job_args)
          return 0.0 if !job_limit || count(*job_args) < job_limit

          job_period = period(job_args)
          job_key = key(job_args)
          time_since_oldest = Time.now.to_f - Sidekiq.redis { |redis| redis.lindex(job_key, -1) }.to_f
          if time_since_oldest > job_period
            # The oldest job on our list is from more than the throttling period ago,
            # which means we have not hit the limit this period.
            0.0
          else
            # If we can only have X jobs every Y minutes, then wait until Y minutes have elapsed
            # since the oldest job on our list.
            job_period - time_since_oldest
          end
        end

        # @return [Integer] Current count of jobs
        def count(*job_args)
          Sidekiq.redis { |conn| conn.llen(key(job_args)) }.to_i
        end

        # Marks job as not processing.
        # No tracking of this is necessary for threshold.
        # @return [void]
        def finalize!(...); end

        # Resets count of jobs
        # @return [void]
        def reset!(*job_args)
          Sidekiq.redis { |conn| conn.del(key(job_args)) }
        end
      end
    end
  end
end
