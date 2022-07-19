# frozen_string_literal: true

# 3rd party
require "sidekiq"

# internal
require "sidekiq/throttled/version"
require "sidekiq/throttled/configuration"
require "sidekiq/throttled/registry"
require "sidekiq/throttled/job"
require "sidekiq/throttled/worker"
require "sidekiq/throttled/utils"

# @see https://github.com/mperham/sidekiq/
module Sidekiq
  # Concurrency and threshold throttling for Sidekiq.
  #
  # Just add somewhere in your bootstrap:
  #
  #     require "sidekiq/throttled"
  #     Sidekiq::Throttled.setup!
  #
  # Once you've done that you can include {Sidekiq::Throttled::Job} to your
  # job classes and configure throttling:
  #
  #     class MyJob
  #       include Sidekiq::Job
  #       include Sidekiq::Throttled::Job
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
      include Utils

      # @return [Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # Hooks throttler into sidekiq.
      #
      # @return [void]
      def setup!
        Sidekiq.configure_server do |config|
          setup_strategy!(config)

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
        job = message.fetch("wrapped") { message.fetch("class") { return false } }
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

      # @return [void]
      def setup_strategy!(sidekiq_config)
        require "sidekiq/throttled/fetch"

        # https://github.com/mperham/sidekiq/commit/67daa7a408b214d593100f782271ed108686c147
        sidekiq_config = sidekiq_config.options if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("6.5.0")

        sidekiq_config[:fetch] = Sidekiq::Throttled::Fetch.new(sidekiq_config)
      end

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
    end
  end
end
