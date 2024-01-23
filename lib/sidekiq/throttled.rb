# frozen_string_literal: true

require "sidekiq"

require_relative "./throttled/config"
require_relative "./throttled/cooldown"
require_relative "./throttled/job"
require_relative "./throttled/middlewares/server"
require_relative "./throttled/registry"
require_relative "./throttled/version"
require_relative "./throttled/worker"

# @see https://github.com/mperham/sidekiq/
module Sidekiq
  # Concurrency and threshold throttling for Sidekiq.
  #
  # Just add somewhere in your bootstrap:
  #
  #     require "sidekiq/throttled"
  #     Sidekiq::Throttled.setup!
  #
  # Note that if you’re using Sidekiq Pro’s SuperFetch feature, the call to
  # activate SuperFetch (e.g., {config.super_fetch!}) must come before the
  # call to {.setup!}. If you fail to do so, existing throttles will not be
  # cleared correctly for recovered orphaned jobs. To be on the safe side,
  # add the {.setup!} call to the bottom of your init file.
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

    @config   = Config.new.freeze
    @cooldown = Cooldown[@config]

    class << self
      # @api internal
      #
      # @return [Cooldown, nil]
      attr_reader :cooldown

      # @example
      #   Sidekiq::Throttled.configure do |config|
      #     config.cooldown_period = nil # Disable queues cooldown manager
      #   end
      #
      # @yieldparam config [Config]
      def configure
        MUTEX.synchronize do
          config = @config.dup

          yield config

          @config   = config.freeze
          @cooldown = Cooldown[@config]
        end
      end

      # Tells whenever job is throttled or not.
      #
      # @param [String] message Job's JSON payload
      # @return [Boolean]
      def throttled?(message)
        with_strategy_and_job(message) do |strategy, jid, args|
          return strategy.throttled?(jid, *args)
        end

        false
      rescue StandardError
        false
      end

      # Manually reset throttle for job that had previously been orphaned but has been recovered since.
      #
      # @param [String] message Job's JSON payload
      # @return [Boolean]
      def recover!(message)
        with_strategy_and_job(message) do |strategy, jid, args|
          strategy.finalize!(jid, *args)

          return true
        end

        false
      rescue StandardError
        false
      end

      def setup!
        require_relative "./throttled/patches/basic_fetch"
        require_relative "./throttled/patches/super_fetch" if Sidekiq.pro?

        Sidekiq.configure_server do |sidekiq_config|
          configure_orphan_handler(sidekiq_config) if Sidekiq.pro?

          configure_middleware(sidekiq_config)
        end
      end

      private

      def configure_orphan_handler(sidekiq_config)
        wrapped_orphan_handler = sidekiq_config[:fetch_setup]

        sidekiq_config[:fetch_setup] = build_orphan_handler(wrapped_orphan_handler)
      end

      def configure_middleware(sidekiq_config)
        sidekiq_config.server_middleware do |chain|
          chain.add(Sidekiq::Throttled::Middlewares::Server)
        end
      end

      def with_strategy_and_job(message)
        message = Sidekiq.load_json(message)
        job     = message.fetch("wrapped") { message["class"] }
        jid     = message["jid"]

        return unless job && jid

        strategy = Registry.get(job)

        yield(strategy, jid, message["args"])
      end

      # Ensure recovered orphaned jobs are unthrottled
      def build_orphan_handler(wrapped_orphan_handler)
        proc do |message, pill|
          recover!(message)

          wrapped_orphan_handler&.call(message, pill)
        end
      end
    end
  end
end
