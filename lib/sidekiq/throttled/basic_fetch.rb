# frozen_string_literal: true

require "sidekiq"
require "sidekiq/fetch"

module Sidekiq
  module Throttled
    # Default Sidekiq's BasicFetch infused with Throttler.
    #
    # @private
    class BasicFetch < Sidekiq::BasicFetch
      # Retrieves job from redis.
      #
      # @return [Sidekiq::Throttled::UnitOfWork, nil]
      def retrieve_work
        work = super

        if work && Throttled.throttled?(work.job)
          requeue_throttled(work)
          return nil
        end

        work
      end

      private

      # Pushes job back to the head of the queue, so that job won't be tried
      # immediately after it was requeued (in most cases).
      #
      # @note This is triggered when job is throttled. So it is same operation
      #   Sidekiq performs upon `Sidekiq::Worker.perform_async` call.
      #
      # @return [void]
      def requeue_throttled(work)
        redis { |conn| conn.lpush(work.queue, work.job) }
      end

      # Returns list of queues to try to fetch jobs from.
      #
      # @note It may return an empty array.
      # @param [Array<String>] queues
      # @return [Array<String>]
      def queues_cmd
        queues = super

        # TODO: Refactor to be prepended as an integration mixin during configuration stage
        #   Or via configurable queues reducer
        queues -= Sidekiq::Pauzer.paused_queues.map { |name| "queue:#{name}" } if defined?(Sidekiq::Pauzer)

        queues
      end
    end
  end
end
