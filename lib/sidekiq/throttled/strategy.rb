# frozen_string_literal: true

# external
require "json"
require "redis_prescription"

# internal
require_relative "./errors"
require_relative "./strategy_collection"
require_relative "./strategy/concurrency"
require_relative "./strategy/threshold"
require_relative "./message"

module Sidekiq
  module Throttled
    # Meta-strategy that couples {Concurrency} and {Threshold} strategies.
    #
    # @private
    class Strategy # rubocop:disable Metrics/ClassLength
      MULTI_STRATEGY_SCRIPT = RedisPrescription.new(
        File.read("#{__dir__}/strategy/multi_strategy_throttled.lua")
      )
      private_constant :MULTI_STRATEGY_SCRIPT

      # :enqueue means put the job back at the end of the queue immediately
      # :schedule means schedule enqueueing the job for a later time when we expect to have capacity
      VALID_VALUES_FOR_REQUEUE_WITH = %i[enqueue schedule].freeze

      attr_reader :concurrency, :threshold, :observer, :requeue_options

      def self.throttled_for(strategies, jid, job_args)
        job_args = Array(job_args)
        payloads, keys, payload_types, payload_strategy_indexes =
          collect_strategy_payloads(strategies, jid, job_args, Time.now.to_f)
        return [false, []] if payloads.empty?

        per_strategy_results = execute_multi_strategy_script(keys, payloads)
        return [false, []] unless per_strategy_results

        throttled_strategies = process_throttled_strategies(
          strategies, per_strategy_results, payload_types, payload_strategy_indexes, job_args
        )
        [true, throttled_strategies.uniq]
      end

      def self.collect_strategy_payloads(strategies, jid, job_args, now)
        collections = { payloads: [], keys: [], types: [], indexes: [] }
        job_context = { jid: jid, job_args: job_args, now: now }

        strategies.each_with_index do |strategy, index|
          append_strategy_payload(strategy, index, job_context, collections)
        end

        [collections[:payloads], collections[:keys], collections[:types], collections[:indexes]]
      end
      private_class_method :collect_strategy_payloads

      def self.append_strategy_payload(strategy, index, job_context, collections)
        strategy_payloads, strategy_keys, strategy_types =
          strategy.send(:throttled_components, job_context[:jid], job_context[:job_args], job_context[:now])
        return if strategy_payloads.empty?

        collections[:payloads].concat(strategy_payloads)
        collections[:keys].concat(strategy_keys)
        collections[:types].concat(strategy_types)
        collections[:indexes].concat([index] * strategy_payloads.length)
      end
      private_class_method :append_strategy_payload

      def self.execute_multi_strategy_script(keys, payloads)
        any_throttled, *per_strategy = Sidekiq.redis do |redis|
          MULTI_STRATEGY_SCRIPT.call(redis, keys: keys, argv: [JSON.generate(payloads)])
        end
        per_strategy if any_throttled.to_i == 1
      end
      private_class_method :execute_multi_strategy_script

      def self.process_throttled_strategies(strategies, per_strategy, payload_types, payload_strategy_indexes, job_args)
        throttled_types_by_strategy = build_throttled_types_map(per_strategy, payload_types, payload_strategy_indexes)

        throttled_strategies = []
        throttled_types_by_strategy.each do |strategy_index, types|
          strategy = strategies[strategy_index]
          notify_strategy_observers(strategy, types, job_args)
          throttled_strategies << strategy
        end
        throttled_strategies
      end
      private_class_method :process_throttled_strategies

      def self.build_throttled_types_map(per_strategy, payload_types, payload_strategy_indexes)
        throttled_types_by_strategy = Hash.new { |hash, key| hash[key] = [] }
        per_strategy.each_with_index do |result, payload_index|
          next unless result.to_i == 1

          strategy_index = payload_strategy_indexes[payload_index]
          throttled_types_by_strategy[strategy_index] << payload_types[payload_index]
        end
        throttled_types_by_strategy
      end
      private_class_method :build_throttled_types_map

      def self.notify_strategy_observers(strategy, types, job_args)
        strategy.observer&.call(:concurrency, *job_args) if types.include?(:concurrency)
        strategy.observer&.call(:threshold, *job_args) if types.include?(:threshold)
      end
      private_class_method :notify_strategy_observers

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

      def dynamic?
        return true if @concurrency&.dynamic?
        return true if @threshold&.dynamic?

        false
      end

      def throttled?(jid, *job_args)
        job_args = Array(job_args)
        now = Time.now.to_f
        multi_strategy_payloads, multi_strategy_keys, multi_strategy_types =
          throttled_components(jid, job_args, now)
        return false if multi_strategy_payloads.empty?

        per_strategy_results = execute_throttle_check(multi_strategy_keys, multi_strategy_payloads)
        return false unless per_strategy_results

        throttled_and_notify?(multi_strategy_types, per_strategy_results, job_args)
      end

      def requeue_with
        requeue_options[:with]
      end

      def requeue_to
        requeue_options[:to]
      end

      def requeue_throttled(work) # rubocop:disable Metrics/MethodLength
        payload  = Message.new(work.job)
        job_args = Array(payload.job_args)
        with     = resolved_requeue_with(*job_args)

        target_queue = calc_target_queue(work, payload)

        case with
        when :enqueue
          re_enqueue_throttled(work, target_queue)
        when :schedule
          payload.job_id or return false
          reschedule_throttled(work, target_queue)
        else
          raise "unrecognized :with option #{with}"
        end
      end

      def finalize!(jid, *job_args)
        @concurrency&.finalize!(jid, *job_args)
      end

      def resolved_requeue_with(*job_args)
        requeue_with.respond_to?(:call) ? requeue_with.call(*job_args) : requeue_with
      end

      def retry_in(jid, *job_args)
        intervals = [
          @concurrency&.retry_in(jid, *job_args),
          @threshold&.retry_in(*job_args)
        ].compact

        raise "Cannot compute a valid retry interval" if intervals.empty?

        interval = intervals.max
        interval += rand(interval / 5) if interval > 10
        interval
      end

      def reset!
        @concurrency&.reset!
        @threshold&.reset!
      end

      private

      def throttled_components(jid, job_args, now)
        collections = { payloads: [], keys: [], types: [] }

        collect_concurrency_components(jid, job_args, now, collections)
        collect_threshold_components(job_args, now, collections)

        [collections[:payloads], collections[:keys], collections[:types]]
      end

      def collect_concurrency_components(jid, job_args, now, collections)
        @concurrency.each do |strategy|
          job_limit = strategy.limit(job_args)&.to_i
          next if job_limit.nil?

          collections[:payloads] << strategy.multi_strategy_payload(jid, job_args, now, job_limit)
          collections[:keys].concat(strategy.multi_strategy_keys(job_args))
          collections[:types] << :concurrency
        end
      end

      def collect_threshold_components(job_args, now, collections)
        @threshold.each do |strategy|
          job_limit = strategy.limit(job_args)&.to_i
          next if job_limit.nil?

          collections[:payloads] << strategy.multi_strategy_payload(
            job_args, now, job_limit, strategy.period(job_args)
          )
          collections[:keys].concat(strategy.multi_strategy_keys(job_args))
          collections[:types] << :threshold
        end
      end

      def execute_throttle_check(keys, payloads)
        any_throttled, *per_strategy = Sidekiq.redis do |redis|
          MULTI_STRATEGY_SCRIPT.call(redis, keys: keys, argv: [JSON.generate(payloads)])
        end
        per_strategy if any_throttled.to_i == 1
      end

      def throttled_and_notify?(types, per_strategy, job_args)
        if throttled_type?(types, per_strategy, :concurrency)
          @observer&.call(:concurrency, *job_args)
          return true
        end

        if throttled_type?(types, per_strategy, :threshold)
          @observer&.call(:threshold, *job_args)
          return true
        end

        false
      end

      def validate!
        unless VALID_VALUES_FOR_REQUEUE_WITH.include?(@requeue_options[:with]) ||
               @requeue_options[:with].respond_to?(:call)
          raise ArgumentError, "requeue: #{@requeue_options[:with]} is not a valid value for :with"
        end

        raise ArgumentError, "Neither :concurrency nor :threshold given" unless @concurrency.any? || @threshold.any?
      end

      def calc_target_queue(work, payload) # rubocop:disable Metrics/MethodLength
        target = case requeue_to
                 when Proc, Method
                   requeue_to.call(*Array(payload.job_args))
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

      def re_enqueue_throttled(work, target_queue)
        target_queue = "queue:#{target_queue}" unless target_queue.start_with?("queue:")

        case work.class.name
        when "Sidekiq::Pro::SuperFetch::UnitOfWork"
          work.queue = target_queue
          work.requeue
        else
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

      def throttled_type?(types, per_strategy, target)
        per_strategy.each_with_index do |result, index|
          return true if result.to_i == 1 && types[index] == target
        end

        false
      end
    end
  end
end
