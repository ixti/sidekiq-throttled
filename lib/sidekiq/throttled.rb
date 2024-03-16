# frozen_string_literal: true

require "sidekiq"

require_relative "./throttled/config"
require_relative "./throttled/cooldown"
require_relative "./throttled/job"
require_relative "./throttled/middlewares/server"
require_relative "./throttled/patches/basic_fetch"
require_relative "./throttled/patches/super_fetch"
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
        message = Sidekiq.load_json(message)
        job     = message.fetch("wrapped") { message["class"] }
        args    = message.key?("wrapped") ? message.dig("args", 0, "arguments") : message["args"]
        jid     = message["jid"]

        return false unless job && jid

        Registry.get(job) do |strategy|
          return strategy.throttled?(jid, *args)
        end

        false
      rescue StandardError
        false
      end

      # @deprecated Will be removed in 2.0.0
      def setup!
        warn "Sidekiq::Throttled.setup! was deprecated"

        Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.remove(Sidekiq::Throttled::Middlewares::Server)
            chain.add(Sidekiq::Throttled::Middlewares::Server)
          end
        end
      end
    end
  end

  configure_server do |config|
    config.server_middleware do |chain|
      chain.add(Sidekiq::Throttled::Middlewares::Server)
    end
  end
end
