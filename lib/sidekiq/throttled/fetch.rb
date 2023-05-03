# frozen_string_literal: true

require "sidekiq"
require "sidekiq/throttled/expirable_list"
require "sidekiq/throttled/fetch/unit_of_work"
require "sidekiq/throttled/queue_name"

module Sidekiq
  module Throttled
    # Throttled fetch strategy.
    #
    # @private
    class Fetch
      # Timeout to sleep between fetch retries in case of no job received,
      # as well as timeout to wait for redis to give us something to work.
      TIMEOUT = 2

      # Initializes fetcher instance.
      # @param options [Hash]
      # @option options [Boolean] :strict (false)
      # @option options [Array<#to_s>] :queue
      def initialize(options)
        @strict = options[:strict] ? true : false
        @queues = options.fetch(:queues).map { |q| QueueName.expand q }

        raise ArgumentError, "empty :queues" if @queues.empty?

        @queues.uniq! if @strict

        setup(options)
      end

      # @option options [Integer] :throttled_queue_cooldown (TIMEOUT)
      #   Min delay in seconds before queue will be polled again after
      #   throttled job.
      def setup(options)
        @paused = ExpirableList.new(options.fetch(:throttled_queue_cooldown, TIMEOUT))
      end

      # Retrieves job from redis.
      #
      # @return [Sidekiq::Throttled::UnitOfWork, nil]
      def retrieve_work
        work = brpop
        return unless work

        work = UnitOfWork.new(*work)
        return work unless work.throttled?

        work.requeue_throttled
        @paused << QueueName.expand(work.queue_name)

        nil
      end

      def bulk_requeue(units, *)
        return if units.empty?

        Sidekiq.logger.debug { "Re-queueing terminated jobs" }
        Sidekiq.redis do |conn|
          conn.pipelined do |pipeline|
            units.each { |unit| unit.requeue(pipeline) }
          end
        end
        Sidekiq.logger.info("Pushed #{units.size} jobs back to Redis")
      rescue => e
        Sidekiq.logger.warn("Failed to requeue #{units.size} jobs: #{e}")
      end

      private

      # Tries to pop pair of `queue` and job `message` out of sidekiq queues.
      #
      # @see http://redis.io/commands/brpop
      # @return [Array(String, String), nil]
      def brpop
        queues = filter_queues(@strict ? @queues : @queues.shuffle.uniq)

        if queues.size <= 0
          sleep TIMEOUT
          return
        end

        # TODO: Refactor for better redis-client support
        Sidekiq.redis { |conn| conn.brpop(*queues, timeout: TIMEOUT) }
      end

      # Returns list of queues to try to fetch jobs from.
      #
      # @note It may return an empty array.
      # @param [Array<String>] queues
      # @return [Array<String>]
      def filter_queues(queues)
        queues -= @paused.to_a

        # TODO: Refactor to handle this during the setup phase
        queues -= Sidekiq::Pauzer.paused_queues if defined?(Sidekiq::Pauzer)

        queues
      end
    end

    class Fetch7 < Fetch
      def initialize(capsule) # rubocop:disable Lint/MissingSuper
        raise ArgumentError, "missing queue list" unless capsule.queues

        @strict = capsule.mode == :strict
        @queues = capsule.queues.map { |q| QueueName.expand q }
        @queues.uniq! if @strict
      end
    end
  end
end
