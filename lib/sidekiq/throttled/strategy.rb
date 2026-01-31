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
        now = Time.now.to_f
        payloads = []
        keys = []
        payload_types = []
        payload_strategy_indexes = []

        strategies.each_with_index do |strategy, index|
          strategy_payloads, strategy_keys, strategy_types =
            strategy.send(:throttled_components, jid, job_args, now)
          next if strategy_payloads.empty?

          payloads.concat(strategy_payloads)
          keys.concat(strategy_keys)
          payload_types.concat(strategy_types)
          payload_strategy_indexes.concat([index] * strategy_payloads.length)
        end

        return [false, []] if payloads.empty?

        any_throttled, *per_strategy = Sidekiq.redis do |redis|
          MULTI_STRATEGY_SCRIPT.call(
            redis,
            keys: keys,
            argv: [JSON.generate(payloads)]
          )
        end

        unless any_throttled.to_i == 1
          payload_strategy_indexes.uniq.each do |strategy_index|
            strategies[strategy_index].finalize!(jid, *job_args)
          end

          return [false, []]
        end

        throttled_types_by_strategy = Hash.new { |hash, key| hash[key] = [] }
        per_strategy.each_with_index do |result, payload_index|
          next unless result.to_i == 1

          strategy_index = payload_strategy_indexes[payload_index]
          throttled_types_by_strategy[strategy_index] << payload_types[payload_index]
        end

        throttled_strategies = []
        throttled_types_by_strategy.each do |strategy_index, types|
          strategy = strategies[strategy_index]

          if types.include?(:concurrency)
            strategy.observer&.call(:concurrency, *job_args)
          end
          
          if types.include?(:threshold)
            strategy.observer&.call(:threshold, *job_args)
          end

          throttled_strategies << strategy
        end

        [true, throttled_strategies.uniq]
      end

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

        any_throttled, *per_strategy = Sidekiq.redis do |redis|
          MULTI_STRATEGY_SCRIPT.call(
            redis,
            keys: multi_strategy_keys,
            argv: [JSON.generate(multi_strategy_payloads)]
          )
        end

        return false unless any_throttled.to_i == 1

        if throttled_type?(multi_strategy_types, per_strategy, :concurrency)
          @observer&.call(:concurrency, *job_args)
          return true
        end

        if throttled_type?(multi_strategy_types, per_strategy, :threshold)
          @observer&.call(:threshold, *job_args)
          return true
        end

        false
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
          jid = payload.job_id or return false
          reschedule_throttled(work, target_queue, payload, jid, job_args)
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
        multi_strategy_payloads = []
        multi_strategy_keys = []
        multi_strategy_types = []

        @concurrency.each do |strategy|
          job_limit = strategy.limit(job_args)
          next if job_limit.nil?
          job_limit = job_limit.to_i

          multi_strategy_payloads << strategy.multi_strategy_payload(jid, job_args, now, job_limit)
          multi_strategy_keys.concat(strategy.multi_strategy_keys(job_args))
          multi_strategy_types << :concurrency
        end

        @threshold.each do |strategy|
          job_limit = strategy.limit(job_args)
          next if job_limit.nil?
          job_limit = job_limit.to_i

          multi_strategy_payloads << strategy.multi_strategy_payload(
            job_args,
            now,
            job_limit,
            strategy.period(job_args)
          )
          multi_strategy_keys.concat(strategy.multi_strategy_keys(job_args))
          multi_strategy_types << :threshold
        end

        [multi_strategy_payloads, multi_strategy_keys, multi_strategy_types]
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

      def reschedule_throttled(work, target_queue, payload, jid, job_args)
        target_queue = target_queue.delete_prefix("queue:")
        job_class    = payload.job_class or return false

        Sidekiq::Client.enqueue_to_in(
          target_queue,
          retry_in(jid, *job_args),
          Object.const_get(job_class),
          *job_args
        )

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
