# frozen_string_literal: true
# internal
require "sidekiq/throttled/strategy/script"

module Sidekiq
  module Throttled
    class Strategy
      # Threshold throttling strategy
      # @todo Use redis TIME command instead of sending current timestamp from
      #   sidekiq manager. See: http://redis.io/commands/time
      class Threshold
        # LUA script used to limit fetch threshold.
        # Logic behind the scene can be described in following pseudo code:
        #
        #     def exceeded?
        #       limit <= LLEN(@key) && NOW - LINDEX(@key, -1) < period
        #     end
        #
        #     def increase!
        #       LPUSH(@key, NOW)
        #       LTRIM(@key, 0, limit - 1)
        #       EXPIRE(@key, period)
        #     end
        #
        #     return 1 if exceeded?
        #
        #     increase!
        #     return 0
        SCRIPT = Script.new File.read "#{__dir__}/threshold.lua"
        private_constant :SCRIPT

        # @!attribute [r] limit
        #   @return [Integer] Amount of jobs allowed per period
        def limit(job_args = nil)
          if @_limit.respond_to?(:call)
            @_limit.call(job_args)
          else
            @_limit
          end.to_i
        end

        # @!attribute [r] period
        #   @return [Float] Period in seconds
        def period(job_args = nil)
          if @_period.respond_to?(:call)
            @_period.call(job_args)
          else
            @_period
          end.to_f
        end

        # @param [#to_s] strategy_key
        # @param [Hash] opts
        # @option opts [#to_i] :limit Amount of jobs allowed per period
        # @option opts [#to_f] :period Period in seconds
        def initialize(strategy_key, opts)
          @base_key = "#{strategy_key}:threshold".freeze
          @_limit  = opts[:limit]
          @_period = opts[:period]
          @key_suffix = opts[:key_suffix]
        end

        def dynamic_limit?
          @_limit.respond_to?(:call) || @_period.respond_to?(:call)
        end

        def dynamic_keys?
          @key_suffix
        end

        # @return [Boolean] whenever job is throttled or not
        def throttled?(*job_args)
          key = key(job_args)
          limit = limit(job_args)
          period = period(job_args)
          1 == SCRIPT.eval([key], [limit, period, Time.now.to_f])
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

        private

        def key(job_args)
          key = @base_key.dup
          key << ":#{@key_suffix.call(*job_args)}" if @key_suffix
          key
        end
      end
    end
  end
end
