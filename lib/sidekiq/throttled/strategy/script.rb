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
        LOAD = "load"
        private_constant :LOAD

        # Redis error fired when script ID is unkown
        NOSCRIPT = "NOSCRIPT"
        private_constant :NOSCRIPT

        # LUA script source.
        # @return [String]
        attr_reader :source

        # LUA script SHA1 digest.
        # @return [String]
        attr_reader :digest

        # @param [#to_s] source Lua script
        # @param [Logger] logger
        def initialize(source, logger: Sidekiq.logger)
          @source = source.to_s.strip.freeze
          @digest = Digest::SHA1.hexdigest(@source).freeze
          @logger = logger
        end

        # Loads script to redis
        # @return [void]
        def bootstrap!
          namespaceless_redis do |conn|
            digest = conn.script(LOAD, @source)

            # XXX: this may happen **ONLY** if script digesting will be
            #   changed in redis, which is not likely gonna happen.
            unless @digest == digest
              if @logger
                @logger.warn "Unexpected script SHA1 digest: " \
                  "#{digest.inspect} (expected: #{@digest.inspect})"
              end

              @digest = digest.freeze
            end
          end
        end

        # Executes script and returns result of execution
        # @return Result of script execution
        def eval(*args)
          Sidekiq.redis do |conn|
            begin
              conn.evalsha(@digest, *args)
            rescue => e
              raise unless e.message.include? NOSCRIPT
              bootstrap!
              conn.evalsha(@digest, *args)
            end
          end
        end

        # Reads given file and returns new {Script} with its contents.
        # @return [Script]
        def self.read(file)
          new File.read file
        end

        private

        # Yields real namespace-less redis client.
        def namespaceless_redis
          Sidekiq.redis do |conn|
            if defined?(Redis::Namespace) && conn.is_a?(Redis::Namespace)
              conn = conn.redis
            end

            yield conn
          end
        end
      end
    end
  end
end
