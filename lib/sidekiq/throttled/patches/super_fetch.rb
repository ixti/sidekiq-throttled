# frozen_string_literal: true

require "sidekiq"

module Sidekiq
  module Throttled
    module Patches
      module SuperFetch
        # Retrieves job from redis.
        #
        # @return [Sidekiq::Throttled::UnitOfWork, nil]
        def retrieve_work
          work = super

          if work && Throttled.throttled?(work.job)
            Throttled.cooldown&.notify_throttled(work.queue)
            requeue_throttled(work)
            return nil
          end

          Throttled.cooldown&.notify_admitted(work.queue) if work

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
          if work.respond_to?(:local_queue)
            # if a SuperFetch UnitOfWork, SuperFetch will requeue it using lpush
            work.requeue
          else
            # Fallback to BasicFetch behavior
            redis { |conn| conn.lpush(work.queue, work.job) }
          end
        end

        # Returns list of non-paused queues to try to fetch jobs from.
        #
        # @note It may return an empty array.
        # @return [Array<Array(String, String)>]
        def active_queues
          throttled_queues = Throttled.cooldown&.queues&.to_a&.to_h { [_1, true] }
          return super unless throttled_queues
          
          super.reject { |queue, _private_queue| throttled_queues[queue] }
        end
      end
    end
  end
end

begin
  require "sidekiq/pro/super_fetch"
  Sidekiq::Pro::SuperFetch.prepend(Sidekiq::Throttled::Patches::SuperFetch)
rescue LoadError
  # Sidekiq Pro is not available
end
