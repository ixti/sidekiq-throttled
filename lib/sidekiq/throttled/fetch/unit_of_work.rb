# frozen_string_literal: true

require "sidekiq"

require "sidekiq/throttled/queue_name"

module Sidekiq
  module Throttled
    class Fetch
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
        # succeccfully processed. Most likely this is used by `ReliableFetch`
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

        # Pushes job back to the tail of the queue, so that it will be popped
        # first next time fetcher will pull job.
        #
        # @note This is triggered when job was not finished and Sidekiq server
        #   process was terminated. It is a reverse of whatever fetcher was
        #   doing to pull the job out of queue.
        #
        # @param [Redis] pipelined connection for requeing via Redis#pipelined
        # @return [void]
        def requeue(pipeline = nil)
          if pipeline
            pipeline.rpush(QueueName.expand(queue_name), job)
          else
            Sidekiq.redis { |conn| conn.rpush(QueueName.expand(queue_name), job) }
          end
        end

        # Pushes job back to the head of the queue, so that job won't be tried
        # immediately after it was requeued (in most cases).
        #
        # @note This is triggered when job is throttled. So it is same operation
        #   Sidekiq performs upon `Sidekiq::Worker.perform_async` call.
        #
        # @return [void]
        def requeue_throttled
          Sidekiq.redis { |conn| conn.lpush(QueueName.expand(queue_name), job) }
        end

        # Tells whenever job should be pushed back to queue (throttled) or not.
        #
        # @see Sidekiq::Throttled.throttled?
        # @return [Boolean]
        def throttled?
          Throttled.throttled? job
        end
      end
    end
  end
end
