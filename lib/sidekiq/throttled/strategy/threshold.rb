# frozen_string_literal: true

require "redis-prescription"

require "sidekiq/throttled/strategy/base"

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

          Sidekiq.redis do |redis|
            1 == SCRIPT.eval(redis, :keys => keys, :argv => argv)
          end
        end

        # @return [Integer] Current count of jobs
        def count(*job_args)
          Sidekiq.redis { |conn| conn.llen(key(job_args)) }.to_i
        end

        # Resets count of jobs
        # @return [void]
        def reset!(*job_args)
          Sidekiq.redis { |conn| conn.del(key(job_args)) }
        end
      end
    end
  end
end
