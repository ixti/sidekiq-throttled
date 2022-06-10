# frozen_string_literal: true

require "sidekiq/throttled/communicator/exception_handler"

module Sidekiq
  module Throttled
    class Communicator
      # Redis subscription listener thread.
      #
      # @private
      class Listener < Thread
        include ExceptionHandler

        # Starts listener thread.
        #
        # @param [String] channel Redis pub/sub channel to listen
        # @param [Callbacks] callbacks Message callbacks registry
        def initialize(channel, callbacks)
          @channel    = channel
          @callbacks  = callbacks
          @terminated = false
          @subscribed = false

          super { listen until @terminated }
        end

        # Whenever underlying redis client subscribed to pub/sup channel.
        #
        # @return [Boolean]
        def ready?
          @subscribed
        end

        # Whenever main loop is still running.
        #
        # @return [Boolean]
        def listening?
          !@terminated
        end

        # Stops listener.
        #
        # @return [void]
        def stop
          # Raising exception while client is in subscription mode makes
          # redis close connection and thus causing ConnectionPool reopen
          # it (normal mode). Otherwise subscription mode client will be
          # pushed back to ConnectionPool causing problems.
          raise Sidekiq::Shutdown
        end

        private

        # Wraps {#subscribe} with exception handlers:
        #
        # - `Sidekiq::Shutdown` exception marks listener as stopped and returns
        #   making `while` loop of listener thread terminate.
        #
        # - `StandardError` got recorded to the log and swallowed,
        #   making `while` loop of the listener thread restart.
        #
        # - `Exception` is recorded to the log and re-raised.
        #
        # @return [void]
        def listen # rubocop:disable Metrics/MethodLength
          subscribe
        rescue Sidekiq::Shutdown
          @terminated = true
          @subscribed = false
        rescue StandardError => e # rubocop:disable Style/RescueStandardError
          @subscribed = false
          handle_exception(e, { :context => "sidekiq:throttled" })
          sleep 1
        rescue Exception => e # rubocop:disable Lint/RescueException
          @terminated = true
          @subscribed = false
          handle_exception(e, { :context => "sidekiq:throttled" })
          raise
        end

        # Subscribes to channel and triggers all registerd handlers for
        # received messages.
        #
        # @note Puts thread's Redis connection to subscription mode and
        #   locks thread.
        #
        # @see http://redis.io/topics/pubsub
        # @see http://redis.io/commands/subscribe
        # @see Callbacks#run
        # @return [void]
        def subscribe # rubocop:disable Metrics/MethodLength
          Sidekiq.redis do |conn|
            conn.subscribe @channel do |on|
              on.subscribe do
                @subscribed = true
                @callbacks.run("ready")
              end

              on.message do |_channel, data|
                message, payload = Marshal.load(data) # rubocop:disable Security/MarshalLoad:
                @callbacks.run("message:#{message}", payload)
              end
            end
          end
        end
      end
    end
  end
end
