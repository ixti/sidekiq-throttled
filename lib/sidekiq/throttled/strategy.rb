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

      REQUEUE_STRATEGIES = %i[enqueue schedule].freeze

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

        raise ArgumentError, "Neither :concurrency nor :threshold given" unless @concurrency.any? || @threshold.any?

        return if REQUEUE_STRATEGIES.include?(@requeue_strategy)

        raise ArgumentError, "#{requeue_strategy} is not a valid :requeue_strategy"
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

      # Return throttled job to be executed later. Implementation depends on the requeue_strategy.
      #
      # @return [void]
      def requeue_throttled(work)
        case requeue_strategy
        when :enqueue
          # Push the job back to the head of the queue.
          # This is the same operation Sidekiq performs upon `Sidekiq::Worker.perform_async` call.
          Sidekiq.redis { |conn| conn.lpush(work.queue, work.job) }
        when :schedule
          # Find out when we will next be able to execute this job, and reschedule for then.
          reschedule_throttled(work)
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

      private

      def reschedule_throttled(work)
        message = JSON.parse(work.job)
        jid = message.fetch("jid") { return false }
        job_class = message.fetch("wrapped") { message.fetch("class") { return false } }
        job_args = message["args"]

        retry_in = [@concurrency&.retry_in(jid, *job_args), @threshold&.retry_in(*job_args)].compact.max

        Sidekiq::Client.enqueue_to_in(work.queue, retry_in, Object.const_get(job_class), *job_args)
      end
    end
  end
end
