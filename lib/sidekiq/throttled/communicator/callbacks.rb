# frozen_string_literal: true

require "fiber"

require "sidekiq/exception_handler"

module Sidekiq
  module Throttled
    class Communicator
      # Callbacks registry and runner. Runs registered callbacks in dedicated
      # Fiber solving issue with ConnectionPool and Redis client in subscriber
      # mode.
      #
      # Once Redis entered subscriber mode `#subscribe` method, it can't be used
      # for any command but pub/sub or quit, making it impossible to use for
      # anything else. ConnectionPool binds reserved client to Thread, thus
      # nested `#with` calls inside same thread result into a same connection.
      # That makes it impossible to issue any normal Redis commands from
      # within listener Thread.
      #
      # @private
      class Callbacks
        include ExceptionHandler

        # Initializes callbacks registry.
        def initialize
          @mutex    = Mutex.new
          @handlers = Hash.new { |h, k| h[k] = [] }
        end

        # Registers handler of given event.
        #
        # @example
        #
        #   callbacks.on "and out comes wolves" do |who|
        #     puts "#{who} let the dogs out?!"
        #   end
        #
        # @param [#to_s] event
        # @raise [ArgumentError] if no handler block given
        # @yield [*args] Runs given block upon `event`
        # @yieldreturn [void]
        # @return [self]
        def on(event, &handler)
          raise ArgumentError, "No block given" unless handler

          @mutex.synchronize { @handlers[event.to_s] << handler }
          self
        end

        # Runs event handlers with given args.
        #
        # @param [#to_s] event
        # @param [Object] payload
        # @return [void]
        def run(event, payload = nil) # rubocop:disable Metrics/MethodLength
          @mutex.synchronize do
            fiber = Fiber.new do
              @handlers[event.to_s].each do |callback|
                begin
                  callback.call(payload)
                rescue => e
                  handle_exception(e, :context => "sidekiq:throttled")
                end
              end
            end

            fiber.resume
          end
        end
      end
    end
  end
end
