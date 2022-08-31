# frozen_string_literal: true

require "sidekiq"
require "sidekiq/throttled/expirable_list"
require "sidekiq/throttled/fetch/unit_of_work"
require "sidekiq/throttled/queues_pauser"
require "sidekiq/throttled/queue_name"

module Sidekiq
  module Throttled
    # Throttled fetch strategy.
    #
    # @private
    class Fetch
      module BulkRequeue
        # Requeues all given units as a single operation.
        #
        # @see http://www.rubydoc.info/github/redis/redis-rb/master/Redis#pipelined-instance_method
        # @param [Array<Fetch::UnitOfWork>] units
        # @return [void]
        def bulk_requeue(units, _options)
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
      end

      # https://github.com/mperham/sidekiq/commit/fce05c9d4b4c0411c982078a4cf3a63f20f739bc
      if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("6.1.0")
        extend BulkRequeue
      else
        include BulkRequeue
      end
      # Timeout to sleep between fetch retries in case of no job received,
      # as well as timeout to wait for redis to give us something to work.
      TIMEOUT = 2

      # Initializes fetcher instance.
      # @param options [Hash]
      # @option options [Integer] :throttled_queue_cooldown (TIMEOUT)
      #   Min delay in seconds before queue will be polled again after
      #   throttled job.
      # @option options [Boolean] :strict (false)
      # @option options [Array<#to_s>] :queue
      def initialize(options)
        @paused = ExpirableList.new(options.fetch(:throttled_queue_cooldown, TIMEOUT))

        @strict = options.fetch(:strict, false)
        @queues = options.fetch(:queues).map { |q| QueueName.expand q }

        raise ArgumentError, "empty :queues" if @queues.empty?

        @queues.uniq! if @strict
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

      private

      # Tries to pop pair of `queue` and job `message` out of sidekiq queues.
      #
      # @see http://redis.io/commands/brpop
      # @return [Array(String, String), nil]
      def brpop
        queues = filter_queues(@strict ? @queues : @queues.shuffle.uniq)

        if queues.empty?
          sleep TIMEOUT
          return
        end

        Sidekiq.redis { |conn| conn.brpop(*queues, :timeout => TIMEOUT) }
      end

      # Returns list of queues to try to fetch jobs from.
      #
      # @note It may return an empty array.
      # @param [Array<String>] queues
      # @return [Array<String>]
      def filter_queues(queues)
        QueuesPauser.instance.filter(queues) - @paused.to_a
      end
    end
  end
end
