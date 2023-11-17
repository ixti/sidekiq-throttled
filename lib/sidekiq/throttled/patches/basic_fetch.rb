# frozen_string_literal: true

require "sidekiq"
require "sidekiq/fetch"

module Sidekiq
  module Throttled
    module Patches
      module BasicFetch
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
      end
    end
  end
end

Sidekiq::BasicFetch.prepend(Sidekiq::Throttled::Patches::BasicFetch)
