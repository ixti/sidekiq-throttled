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

      # @param [#to_s] name
      # @param [Hash] concurrency Concurrency options.
      #   See keyword args of {Strategy::Concurrency#initialize} for details.
      # @param [Hash] threshold Threshold options.
      #   See keyword args of {Strategy::Threshold#initialize} for details.
      # @param [#call] key_suffix Dynamic key suffix generator.
      # @param [#call] observer Process called after throttled.
      def initialize(name, concurrency: nil, threshold: nil, key_suffix: nil, observer: nil)
        @observer = observer

        @concurrency = StrategyCollection.new(concurrency,
          strategy:   Concurrency,
          name:       name,
          key_suffix: key_suffix)

        @threshold = StrategyCollection.new(threshold,
          strategy:   Threshold,
          name:       name,
          key_suffix: key_suffix)

        raise ArgumentError, "Neither :concurrency nor :threshold given" unless @concurrency.any? || @threshold.any?
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

      # Return throttled job to be executed later. Implementation depends on the value of `with`:
      # :enqueue means put the job back at the end of the queue immediately
      # :schedule means schedule enqueueing the job for a later time when we expect to have capacity
      #
      # @param [#to_s] with How to handle the throttled job
      # @param [#to_s] to Name of the queue to re-queue the job to. If not specified, will use the job's original queue.
      # @return [void]
      def requeue_throttled(work, with:, to: nil)
        case with
        when :enqueue
          # Push the job back to the head of the queue.
          target_list = to.nil? ? work.queue : "queue:#{to}"

          # This is the same operation Sidekiq performs upon `Sidekiq::Worker.perform_async` call.
          Sidekiq.redis { |conn| conn.lpush(target_list, work.job) }
        when :schedule
          # Find out when we will next be able to execute this job, and reschedule for then.
          reschedule_throttled(work, to: to)
        else
          raise "unrecognized :with option #{with}"
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

      def reschedule_throttled(work, to: nil)
        message = JSON.parse(work.job)
        job_class = message.fetch("wrapped") { message.fetch("class") { return false } }
        job_args = message["args"]

        target_queue = to.nil? ? work.queue : "queue:#{to}"
        Sidekiq::Client.enqueue_to_in(target_queue, retry_in(work), Object.const_get(job_class), *job_args)
      end

      def retry_in(work)
        message = JSON.parse(work.job)
        jid = message.fetch("jid") { return false }
        job_args = message["args"]

        # Ask both concurrency and threshold, if relevant, how long minimum until we can retry.
        # If we get two answers, take the longer one.
        interval = [@concurrency&.retry_in(jid, *job_args), @threshold&.retry_in(*job_args)].compact.max

        # Add a random amount of jitter, proportional to the length of the minimum retry time.
        # This helps spread out jobs more evenly and avoid clumps of jobs on the queue.
        interval += rand(interval / 5) if interval > 10

        interval
      end
    end
  end
end
