# frozen_string_literal: true

require "singleton"

require "sidekiq/throttled/communicator/exception_handler"
require "sidekiq/throttled/communicator/listener"
require "sidekiq/throttled/communicator/callbacks"

module Sidekiq
  module Throttled
    # Inter-process communication for sidekiq. It starts listener thread on
    # sidekiq server and listens for incoming messages.
    #
    # @example
    #
    #   # Add incoming message handler for server
    #   Communicator.instance.receive "knock" do |who|
    #     puts "#{who}'s knocking on the door"
    #   end
    #
    #   # Emit message from console
    #   Sidekiq.redis do |conn|
    #     Communicator.instance.transmit(conn, "knock", "ixti")
    #   end
    class Communicator
      include Singleton
      include ExceptionHandler

      # Redis PUB/SUB channel name
      #
      # @see http://redis.io/topics/pubsub
      CHANNEL_NAME = "sidekiq:throttled"
      private_constant :CHANNEL_NAME

      # Initializes singleton instance.
      def initialize
        @callbacks = Callbacks.new
        @listener  = nil
        @mutex     = Mutex.new
      end

      # Starts listener thread.
      #
      # @return [void]
      def start_listener
        @mutex.synchronize do
          @listener ||= Listener.new(CHANNEL_NAME, @callbacks)
        end
      end

      # Stops listener thread.
      #
      # @return [void]
      def stop_listener
        @mutex.synchronize do
          @listener&.stop
          @listener = nil
        end
      end

      # Configures Sidekiq server to start/stop listener thread.
      #
      # @private
      # @return [void]
      def setup!
        Sidekiq.configure_server do |config|
          config.on(:startup) { start_listener }
          config.on(:quiet) { stop_listener }
        end
      end

      # Transmit message to listeners.
      #
      # @example
      #
      #   Sidekiq.redis do |conn|
      #     Communicator.instance.transmit(conn, "knock")
      #   end
      #
      # @param [Redis] redis Redis client
      # @param [#to_s] message
      # @param [Object] payload
      # @return [void]
      def transmit(redis, message, payload = nil)
        redis.publish(CHANNEL_NAME, Marshal.dump([message.to_s, payload]))
      end

      # Add incoming message handler.
      #
      # @example
      #
      #   Communicator.instance.receive "knock" do |payload|
      #     # do something upon `knock` message
      #   end
      #
      # @param [#to_s] message
      # @yield [payload] Runs given block everytime `message` being received.
      # @yieldparam [Object, nil] payload Payload that was transmitted
      # @yieldreturn [void]
      # @return [void]
      def receive(message, &handler)
        @callbacks.on("message:#{message}", &handler)
      end

      # Communicator readiness hook.
      #
      # @yield Runs given block every time listener thread subscribes
      #   to Redis pub/sub channel.
      # @return [void]
      def ready(&handler)
        @callbacks.on("ready", &handler)
        yield if @listener&.ready?
      end
    end
  end
end
