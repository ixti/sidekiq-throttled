# frozen_string_literal: true

# internal
require_relative "./errors"
require_relative "./strategy_collection"
require_relative "./strategy/concurrency"
require_relative "./strategy/threshold"

module Sidekiq
  module Throttled
    # Meta-strategy that couples {Concurrency} and {Threshold} strategies.
    #
    # @private
    class Strategy
      # @!attribute [r] concurrency
      #   @return [Strategy::Concurrency, nil]
      attr_reader :concurrency

      # @!attribute [r] threshold
      #   @return [Strategy::Threshold, nil]
      attr_reader :threshold

      # @!attribute [r] observer
      #   @return [Proc, nil]
      attr_reader :observer

      # @!attribute [r] requeue_strategy
      #   @return [String]
      attr_reader :requeue_strategy

      REQUEUE_STRATEGIES = [:enqueue].freeze

      # @param [#to_s] name
      # @param [Hash] concurrency Concurrency options.
      #   See keyword args of {Strategy::Concurrency#initialize} for details.
      # @param [Hash] threshold Threshold options.
      #   See keyword args of {Strategy::Threshold#initialize} for details.
      # @param [#call] key_suffix Dynamic key suffix generator.
      # @param [#call] observer Process called after throttled.
      # @param [#to_s] requeue_strategy What to do with jobs that are throttled
      def initialize(name, concurrency: nil, threshold: nil, key_suffix: nil, observer: nil, requeue_strategy: :enqueue) # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
        @observer = observer
        @requeue_strategy = requeue_strategy

        @concurrency = StrategyCollection.new(concurrency,
          strategy:   Concurrency,
          name:       name,
          key_suffix: key_suffix)

        @threshold = StrategyCollection.new(threshold,
          strategy:   Threshold,
          name:       name,
          key_suffix: key_suffix)

        unless @concurrency.any? || @threshold.any?
          raise ArgumentError, "Neither :concurrency nor :threshold given"
        end

        unless REQUEUE_STRATEGIES.include?(@requeue_strategy)
          raise ArgumentError, "#{requeue_strategy} is not a valid :requeue_strategy"
        end
      end

      # @return [Boolean] whenever strategy has dynamic config
      def dynamic?
        return true if @concurrency&.dynamic?
        return true if @threshold&.dynamic?

        false
      end

      # @return [Boolean] whenever job is throttled or not.
      def throttled?(jid, *job_args)
        if @concurrency&.throttled?(jid, *job_args)
          @observer&.call(:concurrency, *job_args)
          return true
        end

        if @threshold&.throttled?(*job_args)
          @observer&.call(:threshold, *job_args)

          finalize!(jid, *job_args)
          return true
        end

        false
      end

      # Pushes job back to the head of the queue, so that job won't be tried
      # immediately after it was requeued (in most cases).
      #
      # @note This is triggered when job is throttled. So it is same operation
      #   Sidekiq performs upon `Sidekiq::Worker.perform_async` call.
      #
      # @return [void]
      def requeue_throttled(work)
        case requeue_strategy
        when :enqueue
          Sidekiq.redis { |conn| conn.lpush(work.queue, work.job) }
        else
          raise "unrecognized requeue_strategy #{requeue_strategy}"
        end
      end

      # Marks job as being processed.
      # @return [void]
      def finalize!(jid, *job_args)
        @concurrency&.finalize!(jid, *job_args)
      end

      # Resets count of jobs of all avaliable strategies
      # @return [void]
      def reset!
        @concurrency&.reset!
        @threshold&.reset!
      end
    end
  end
end
