# frozen_string_literal: true

require "sidekiq"

require "sidekiq/throttled/queue_name"

module Sidekiq
  module Throttled
    # BRPOP response envelope.
    #
    # @see Throttled::Fetch
    # @private
    class UnitOfWork
      # @return [String] Redis key where job was pulled from
      attr_reader :queue

      # @return [String] Job's JSON payload
      attr_reader :job

      # @param [String] queue Redis key where job was pulled from
      # @param [String] job Job's JSON payload
      def initialize(queue, job)
        @queue = queue
        @job   = job
      end

      # Callback that is called by `Sidekiq::Processor` when job was
      # succeccfully processed. Most this is used by `ReliableFetch`
      # of Sidekiq Pro/Enterprise to remove job from running queue.
      #
      # @return [void]
      def acknowledge
        # do nothing
      end

      # Normalized `queue` name.
      #
      # @see QueueName.normalize
      # @return [String]
      def queue_name
        @queue_name ||= QueueName.normalize queue
      end

      # Pushes job back to the queue.
      #
      # @note This is triggered when job was not finished and Sidekiq server
      #   process was terminated (shutdowned). Thus it should be reverse of
      #   whatever fetcher was doing to pull the job out of queue.
      #
      # @return [void]
      def requeue
        Sidekiq.redis { |conn| conn.rpush(QueueName.expand(queue_name), job) }
      end
    end
  end
end
