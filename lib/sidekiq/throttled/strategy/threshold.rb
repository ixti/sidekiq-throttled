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
        #       @limit <= LLEN(@key) && NOW - LINDEX(@key, -1) < @period
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
        SCRIPT = Script.new File.read "#{__dir__}/threshold.lua"
        private_constant :SCRIPT

        # @!attribute [r] limit
        #   @return [Integer] Amount of jobs allowed per period
        attr_reader :limit

        # @!attribute [r] period
        #   @return [Float] Period in seconds
        attr_reader :period

        # @param [#to_s] base_key
        # @param [Hash] opts
        # @option opts [#to_i] :limit Amount of jobs allowed per period
        # @option opts [#to_f] :period Period in seconds
        def initialize(base_key, opts)
          @key    = "#{base_key}:threshold".freeze
          @keys   = [@key]
          @limit  = opts.fetch(:limit).to_i
          @period = opts.fetch(:period).to_f
        end

        # @return [Boolean] whenever job is throttled or not
        def throttled?
          1 == SCRIPT.eval(@keys, [@limit, @period, Time.now.to_f])
        end

        # @return [Integer] Current count of jobs
        def count
          Sidekiq.redis { |conn| conn.llen(@key) }.to_i
        end

        # Resets count of jobs
        # @return [void]
        def reset!
          Sidekiq.redis { |conn| conn.del(@key) }
        end
      end
    end
  end
end
