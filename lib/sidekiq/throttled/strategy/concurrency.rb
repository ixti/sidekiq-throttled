# frozen_string_literal: true
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
        SCRIPT = Script.read "#{__dir__}/concurrency.lua"
        private_constant :SCRIPT

        # @param [#to_s] strategy_key
        # @param [Hash] opts
        # @option opts [#to_i] :limit Amount of allowed concurrent jobs
        #   processors running for given key
        # @option opts [#to_i] :ttl (15 minutes) Concurrency lock TTL
        #   in seconds
        # @option opts :key_suffix Proc for dynamic key suffix.
        def initialize(strategy_key, opts)
          @base_key   = "#{strategy_key}:concurrency".freeze
          @limit      = opts.fetch(:limit)
          @ttl        = opts.fetch(:ttl, 900).to_i
          @key_suffix = opts[:key_suffix]
        end

        # @return [Integer] Amount of allowed concurrent job processors
        def limit(job_args = nil)
          return @limit.to_i unless @limit.respond_to? :call
          @limit.call(*job_args).to_i
        end

        # @return [Boolean] Whenever strategy has dynamic config
        def dynamic?
          @key_suffix || @limit.respond_to?(:call)
        end

        # @return [Boolean] whenever job is throttled or not
        def throttled?(jid, *job_args)
          1 == SCRIPT.eval([key(job_args)], [jid.to_s, limit(job_args), @ttl])
        end

        # @return [Integer] Current count of jobs
        def count(*job_args)
          Sidekiq.redis { |conn| conn.scard(key(job_args)) }.to_i
        end

        # Resets count of jobs
        # @return [void]
        def reset!(*job_args)
          Sidekiq.redis { |conn| conn.del(key(job_args)) }
        end

        # Remove jid from the pool of jobs in progress
        # @return [void]
        def finalize!(jid, *job_args)
          Sidekiq.redis { |conn| conn.srem(key(job_args), jid.to_s) }
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
