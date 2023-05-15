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
        # @param [#to_i] ttl Concurrency lock TTL in seconds.
        # @param [Proc] key_suffix Dynamic key suffix generator.
        def initialize(strategy_key, limit:, ttl: 900, key_suffix: nil)
          @base_key   = "#{strategy_key}:concurrency.v2"
          @limit      = limit
          @ttl        = ttl.to_i
          @key_suffix = key_suffix
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

          keys = [key(job_args)]
          argv = [jid.to_s, job_limit, @ttl, Time.now.to_f]

          Sidekiq.redis { |redis| 1 == SCRIPT.call(redis, keys: keys, argv: argv) }
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
          Sidekiq.redis { |conn| conn.zrem(key(job_args), jid.to_s) }
        end
      end
    end
  end
end
