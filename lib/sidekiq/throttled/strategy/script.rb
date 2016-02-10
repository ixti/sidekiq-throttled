# frozen_string_literal: true
module Sidekiq
  module Throttled
    class Strategy
      # Lua script executor for redis.
      #
      # Instead of executing script with `EVAL` everytime - loads script once
      # and then runs it with `EVALSHA`.
      #
      # @private
      class Script
        # Script load command
        LOAD = "load".freeze
        private_constant :LOAD

        # Redis error fired when script ID is unkown
        NOSCRIPT = "NOSCRIPT".freeze
        private_constant :NOSCRIPT

        # @param [#to_s] source Lua script
        def initialize(source)
          @source = source.to_s.strip.freeze
          @sha    = nil
        end

        # Executes script and returns result of execution
        def eval(*args)
          Sidekiq.redis { |conn| conn.evalsha(@sha, *args) }
        rescue => e
          raise unless e.message.include? NOSCRIPT
          load_and_eval(*args)
        end

        private

        # Loads script into redis cache and executes it.
        def load_and_eval(*args)
          Sidekiq.redis do |conn|
            @sha = conn.script(LOAD, @source)
            conn.evalsha(@sha, *args)
          end
        end
      end
    end
  end
end
