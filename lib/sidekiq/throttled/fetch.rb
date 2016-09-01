# frozen_string_literal: true

require "sidekiq"
require "sidekiq/throttled/unit_of_work"
require "sidekiq/throttled/queues_pauser"
require "sidekiq/throttled/queue_name"

module Sidekiq
  module Throttled
    # Throttled fetch strategy.
    #
    # @private
    class Fetch
      TIMEOUT = 2
      private_constant :TIMEOUT

      # Initializes fetcher instance.
      def initialize(options)
        @strict = options[:strict]
        @queues = options[:queues].map { |q| QueueName.expand q }

        @queues.uniq! if @strict
      end

      # @return [Sidekiq::Throttled::UnitOfWork, nil]
      def retrieve_work
        work = brpop
        return unless work

        work = UnitOfWork.new(*work)
        return work unless Throttled.throttled? work.job

        Sidekiq.redis do |conn|
          conn.lpush(QueueName.expand(work.queue_name), work.job)
        end

        nil
      end

      class << self
        def bulk_requeue(units, _options)
          return if units.empty?

          Sidekiq.logger.debug { "Re-queueing terminated jobs" }
          Sidekiq.redis { |conn| conn.pipelined { units.each(&:requeue) } }
          Sidekiq.logger.info("Pushed #{units.size} jobs back to Redis")
        rescue => e
          Sidekiq.logger.warn("Failed to requeue #{units.size} jobs: #{e}")
        end
      end

      private

      # Tries to pop pair of `queue` and job `message` out of sidekiq queue.
      #
      # @see http://redis.io/commands/brpop
      # @return [Array(String, String), nil]
      def brpop
        queues = build_queues_list

        if queues.empty?
          sleep TIMEOUT
          return
        end

        Sidekiq.redis { |conn| conn.brpop(*queues, TIMEOUT) }
      end

      # Returns list of queues to try to fetch jobs from.
      #
      # @note It may return an empty array.
      # @return [Array<String>]
      def build_queues_list
        QueuesPauser.instance.filter(@strict ? @queues : @queues.shuffle.uniq)
      end
    end
  end
end
