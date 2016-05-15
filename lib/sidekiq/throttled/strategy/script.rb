# frozen_string_literal: true

require "digest/sha1"

require "sidekiq"

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

        # LUA script source.
        # @return [String]
        attr_reader :source

        # LUA script SHA1 digest.
        # @return [String]
        attr_reader :digest

        # @param [#to_s] source Lua script
        # @paral [Logger] logger
        def initialize(source, logger: Sidekiq.logger)
          @source = source.to_s.strip.freeze
          @digest = Digest::SHA1.hexdigest(@source).freeze
          @logger = logger
        end

        # Executes script and returns result of execution
        def eval(*args)
          Sidekiq.redis { |conn| conn.evalsha(@digest, *args) }
        rescue => e
          raise unless e.message.include? NOSCRIPT
          load_and_eval(*args)
        end

        private

        # Loads script into redis cache and executes it.
        def load_and_eval(*args)
          Sidekiq.redis do |conn|
            digest = conn.script(LOAD, @source)

            # XXX: this may happen **ONLY** if script digesting will be
            #   changed in redis, which is not likely gonna happen.
            unless @digest == digest
              if @logger
                @logger.warn \
                  "Unexpected script SHA1 digest: " \
                  "#{digest.inspect} (expected: #{@digest.inspect})"
              end

              @digest = digest.freeze
            end

            conn.evalsha(@digest, *args)
          end
        end
      end
    end
  end
end
