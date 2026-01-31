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
  module Throttled
    MUTEX = Mutex.new
    private_constant :MUTEX

    @config   = Config.new.freeze
    @cooldown = Cooldown[@config]

    class << self
      attr_reader :cooldown
      attr_reader :config

      def configure
        MUTEX.synchronize do
          config = @config.dup

          yield config

          @config   = config.freeze
          @cooldown = Cooldown[@config]
        end
      end

      def throttled?(message)
        throttled_with(message).first
      rescue StandardError
        false
      end

      def throttled_with(message)
        message = Message.new(message)
        return [false, []] unless message.job_id

        strategies = strategies_for(message)
        return [false, []] if strategies.empty?

        jid = message.job_id
        job_args = Array(message.job_args)

        throttled, throttled_strategies =
          Strategy.multi_throttled_with(strategies, jid, job_args)

        [throttled, throttled_strategies]
      rescue StandardError
        [false, []]
      end

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
        job_args = Array(message.job_args)

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
