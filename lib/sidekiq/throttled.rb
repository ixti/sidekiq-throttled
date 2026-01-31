# frozen_string_literal: true

require "sidekiq"

require_relative "./throttled/config"
require_relative "./throttled/cooldown"
require_relative "./throttled/job"
require_relative "./throttled/message"
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

      # @api internal
      #
      # @return [Config, nil]
      attr_reader :config

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
        throttled_with(message).first
      rescue StandardError
        false
      end

      # Tells whenever job is throttled or not.
      #
      # @param [String] message Job's JSON payload
      # @return [Array(Boolean, Array<Strategy>)] throttled result and strategies
      def throttled_with(message)
        message = Message.new(message)
        return [false, []] unless message.job_id

        strategies = strategies_for(message)
        return [false, []] if strategies.empty?

        job_args = Array(message.job_args)

        if strategies.length == 1
          strategy = strategies.first
          return [true, [strategy]] if strategy.throttled?(message.job_id, *job_args)

          return [false, []]
        end

        Strategy.throttled_for(strategies, message.job_id, job_args)
      rescue StandardError
        [false, []]
      end

      # Return throttled job to be executed later, delegating the details of how to do that
      # to the Strategy for that job.
      #
      # @return [void]
      def requeue_throttled(work, throttled_strategies = nil)
        message = Message.new(work.job)
        strategies = throttled_strategies || strategies_for(message)
        return if strategies.empty?

        strategy = select_strategy_for_requeue(strategies, message)
        strategy&.requeue_throttled(work)
      end

      private

      def strategies_for(message)
        keys = message.strategy_keys
        keys = [message.job_class] if keys.empty? && message.job_class

        keys.map { |key| Registry.get(key) }.compact.uniq
      end

      def select_strategy_for_requeue(strategies, message)
        jid = message.job_id
        job_args = message.job_args

        strategies
          .map do |strategy|
            with = resolve_requeue_with(strategy, job_args)
            cooldown = with == :schedule ? strategy.retry_in(jid, *job_args) : 0.0

            [cooldown, strategy]
          end
          .max_by { |cooldown, _strategy| cooldown }
          &.last
      end

      def resolve_requeue_with(strategy, job_args)
        strategy.resolved_requeue_with(*job_args)
      end
    end
  end

  configure_server do |config|
    config.server_middleware do |chain|
      chain.add(Sidekiq::Throttled::Middlewares::Server)
    end
  end
end
