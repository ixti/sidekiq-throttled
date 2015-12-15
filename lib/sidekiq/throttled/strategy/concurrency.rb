# internal
require "sidekiq/throttled/strategy/script"

module Sidekiq
  module Throttled
    class Strategy
      # Concurrency throttling strategy
      class Concurrency
        # LUA script used to limit fetch concurrency.
        # Logic behind the scene can be described in following pseudo code:
        #
        #     return 1 if @limit <= LLEN(@key)
        #
        #     PUSH(@key, @jid)
        #     return 0
        SCRIPT = Script.new File.read "#{__dir__}/concurrency.lua"
        private_constant :SCRIPT

        # @!attribute [r] limit
        #   @return [Integer] Amount of allwoed concurrent job processors
        attr_reader :limit

        # @param [#to_s] base_key
        # @param [Hash] opts
        # @option opts [#to_i] :limit Amount of allwoed concurrent jobs
        #   processors running for given key
        # @option opts [#to_i] :ttl (15 minutes) Concurrency lock TTL
        #   in seconds
        def initialize(base_key, opts)
          @key   = "#{base_key}:concurrency".freeze
          @keys  = [@key]
          @limit = opts.fetch(:limit).to_i
          @ttl   = opts.fetch(:ttl, 900).to_i
        end

        # @return [Boolean] whenever job is throttled or not
        def throttled?(jid)
          1 == SCRIPT.eval(@keys, [@limit, @ttl, jid.to_s])
        end

        # @return [Integer] Current count of jobs
        def count
          Sidekiq.redis { |conn| conn.scard(@key) }.to_i
        end

        # Resets count of jobs
        # @return [void]
        def reset!
          Sidekiq.redis { |conn| conn.del(@key) }.to_i
        end

        # Remove jid from the pool of jobs in progress
        # @return [void]
        def finalize!(jid)
          Sidekiq.redis { |conn| conn.srem(@key, jid.to_s) }
        end
      end
    end
  end
end
