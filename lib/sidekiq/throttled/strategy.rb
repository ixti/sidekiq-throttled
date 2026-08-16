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
    class Strategy # rubocop:disable Metrics/ClassLength
      # :enqueue means put the job back at the end of the queue immediately
      # :schedule means schedule enqueueing the job for a later time when we expect to have capacity
      VALID_VALUES_FOR_REQUEUE_WITH = %i[enqueue schedule].freeze

      # @!attribute [r] concurrency
      #   @return [Strategy::Concurrency, nil]
      attr_reader :concurrency

      # @!attribute [r] threshold
      #   @return [Strategy::Threshold, nil]
      attr_reader :threshold

      # @!attribute [r] observer
      #   @return [Proc, nil]
      attr_reader :observer

      # @!attribute [r] requeue_options
      #   @return [Hash, nil]
      attr_reader :requeue_options

      # @param [#to_s] name
      # @param [Hash] concurrency Concurrency options.
      #   See keyword args of {Strategy::Concurrency#initialize} for details.
      # @param [Hash] threshold Threshold options.
      #   See keyword args of {Strategy::Threshold#initialize} for details.
      # @param [#call] key_suffix Dynamic key suffix generator.
      # @param [#call] observer Process called after throttled.
      # @param [#call] requeue What to do with jobs that are throttled.
      def initialize(name, concurrency: nil, threshold: nil, key_suffix: nil, observer: nil, requeue: nil) # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
        @observer = observer

        @concurrency = StrategyCollection.new(concurrency,
          strategy:   Concurrency,
          name:       name,
          key_suffix: key_suffix)

        @threshold = StrategyCollection.new(threshold,
          strategy:   Threshold,
          name:       name,
          key_suffix: key_suffix)

        @requeue_options = Throttled.config.default_requeue_options.merge(requeue || {})

        validate!
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

      # @return [Proc, Symbol] How to requeue the throttled job
      def requeue_with
        requeue_options[:with]
      end

      # @return [String, nil] Name of the queue to re-queue the job to.
      def requeue_to
        requeue_options[:to]
      end

      # Return throttled job to be executed later. Implementation depends on the strategy's `requeue` options.
      # @return [void]
      def requeue_throttled(work) # rubocop:disable Metrics/MethodLength
        # Resolve :with and :to options, calling them if they are Procs
        job_args = JSON.parse(work.job)["args"]
        with = requeue_with.respond_to?(:call) ? requeue_with.call(*job_args) : requeue_with
        target_queue = calc_target_queue(work)

        case with
        when :enqueue
          re_enqueue_throttled(work, target_queue)
        when :schedule
          # Find out when we will next be able to execute this job, and reschedule for then.
          reschedule_throttled(work, target_queue)
        else
          raise "unrecognized :with option #{with}"
        end
      end

      # Marks job as not processing.
      # @return [void]
      def finalize!(jid, *job_args)
        @concurrency&.finalize!(jid, *job_args)
      end

      # Resets count of jobs of all available strategies
      # @return [void]
      def reset!
        @concurrency&.reset!
        @threshold&.reset!
      end

      private

      def validate!
        unless VALID_VALUES_FOR_REQUEUE_WITH.include?(@requeue_options[:with]) ||
               @requeue_options[:with].respond_to?(:call)
          raise ArgumentError, "requeue: #{@requeue_options[:with]} is not a valid value for :with"
        end

        raise ArgumentError, "Neither :concurrency nor :threshold given" unless @concurrency.any? || @threshold.any?
      end

      def calc_target_queue(work) # rubocop:disable Metrics/MethodLength
        target = case requeue_to
                 when Proc, Method
                   requeue_to.call(*JSON.parse(work.job)["args"])
                 when NilClass
                   work.queue
                 when String, Symbol
                   requeue_to
                 else
                   raise ArgumentError, "Invalid argument for `to`"
                 end

        target = work.queue if target.nil? || target.empty?

        target.to_s
      end

      # Push the job back to the head of the queue.
      # The queue name is expected to include the "queue:" prefix, so we add it if it's missing.
      def re_enqueue_throttled(work, target_queue)
        target_queue = "queue:#{target_queue}" unless target_queue.start_with?("queue:")

        case work.class.name
        when "Sidekiq::Pro::SuperFetch::UnitOfWork"
          # Calls SuperFetch UnitOfWork's requeue to remove the job from the
          # temporary queue and push job back to the head of the target queue, so that
          # the job won't be tried immediately after it was requeued (in most cases).
          work.queue = target_queue
          work.requeue
        else
          # This is the same operation Sidekiq performs upon `Sidekiq::Worker.perform_async` call.
          Sidekiq.redis { |conn| conn.lpush(target_queue, work.job) }
        end
      end

      # Reschedule the job to be executed later in the target queue.
      # The queue name should NOT include the "queue:" prefix, so we remove it if it's present.
      def reschedule_throttled(work, target_queue)
        target_queue = target_queue.delete_prefix("queue:")
        message      = JSON.parse(work.job)
        job_class    = message.fetch("wrapped") { message.fetch("class") { return false } }
        job_args     = message["args"]

        # Re-enqueue the job to the target queue at another time as a NEW unit of work
        # AND THEN mark this work as done, so SuperFetch doesn't think this instance is orphaned
        # Technically, the job could processed twice if the process dies between the two lines,
        # but your job should be idempotent anyway, right?
        # The job running twice was already a risk with SuperFetch anyway and this doesn't really increase that risk.
        Sidekiq::Client.enqueue_to_in(target_queue, retry_in(work), Object.const_get(job_class), *job_args)

        work.acknowledge
      end

      def retry_in(work)
        message = JSON.parse(work.job)
        jid = message.fetch("jid") { return false }
        job_args = message["args"]

        # Ask both concurrency and threshold, if relevant, how long minimum until we can retry.
        # If we get two answers, take the longer one.
        intervals = [@concurrency&.retry_in(jid, *job_args), @threshold&.retry_in(*job_args)].compact

        raise "Cannot compute a valid retry interval" if intervals.empty?

        interval = intervals.max

        # Add a random amount of jitter, proportional to the length of the minimum retry time.
        # This helps spread out jobs more evenly and avoid clumps of jobs on the queue.
        interval += rand(interval / 5) if interval > 10

        interval
      end
    end
  end
end
