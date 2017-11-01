# frozen_string_literal: true

# stdlib
require "thread"

# 3rd party
require "sidekiq"

# internal
require "sidekiq/throttled/version"
require "sidekiq/throttled/communicator"
require "sidekiq/throttled/queues_pauser"
require "sidekiq/throttled/registry"
require "sidekiq/throttled/worker"

# @see https://github.com/mperham/sidekiq/
module Sidekiq
  # Concurrency and threshold throttling for Sidekiq.
  #
  # Just add somewhere in your bootstrap:
  #
  #     require "sidekiq/throttled"
  #     Sidekiq::Throttled.setup!
  #
  # Once you've done that you can include {Sidekiq::Throttled::Worker} to your
  # job classes and configure throttling:
  #
  #     class MyWorker
  #       include Sidekiq::Worker
  #       include Sidekiq::Throttled::Worker
  #
  #       sidekiq_options :queue => :my_queue
  #
  #       sidekiq_throttle({
  #         # Allow maximum 10 concurrent jobs of this class at a time.
  #         :concurrency => { :limit => 10 },
  #         # Allow maximum 1K jobs being processed within one hour window.
  #         :threshold => { :limit => 1_000, :period => 1.hour }
  #       })
  #
  #       def perform
  #         # ...
  #       end
  #     end
  module Throttled
    MUTEX = Mutex.new
    private_constant :MUTEX

    class << self
      # Hooks throttler into sidekiq.
      #
      # @return [void]
      def setup!
        Communicator.instance.setup!
        QueuesPauser.instance.setup!

        Sidekiq.configure_server do |config|
          require "sidekiq/throttled/fetch"
          Sidekiq.options[:fetch] = Sidekiq::Throttled::Fetch

          require "sidekiq/throttled/middleware"
          config.server_middleware do |chain|
            chain.add Sidekiq::Throttled::Middleware
          end
        end
      end

      # Tells whenever job is throttled or not.
      #
      # @param [String] message Job's JSON payload
      # @return [Boolean]
      def throttled?(message)
        message = JSON.parse message
        job = message.fetch("class") { return false }
        jid = message.fetch("jid") { return false }

        preload_constant! job

        Registry.get job do |strategy|
          return strategy.throttled?(jid, *message["args"])
        end

        false
      rescue
        false
      end

      private

      # Tries to preload constant by it's name once.
      #
      # Somehow, sometimes, some classes are not eager loaded upon Rails init,
      # leading to throttling config not being registered prior job perform.
      # And that leaves us with concurrency limit + 1 situation upon Sidekiq
      # server restart (becomes normal after all Sidekiq processes handled
      # at leas onr job of that class).
      #
      # @return [void]
      def preload_constant!(job)
        MUTEX.synchronize do
          @preloaded      ||= {}
          @preloaded[job] ||= constantize(job) || true
        end
      end

      # Resolve constant from it's name
      def constantize(str)
        str.sub(/^::/, "").split("::").inject(Object) do |const, name|
          const.const_get(name)
        end
      rescue
        Sidekiq.logger.warn { "Failed to constantize: #{str}" }
        nil
      end
    end
  end
end
