# frozen_string_literal: true

module Sidekiq
  module Throttled
    module Patches
      module ThrottledRetriever
        # Retrieves job from redis.
        #
        # @return [Sidekiq::BasicFetch::UnitOfWork, nil]
        def retrieve_work
          work = super
          return nil unless work

          return nil if work_throttled?(work)

          Throttled.cooldown&.notify_admitted(work.queue)
          work
        end

        private

        def work_throttled?(work)
          throttled, strategies = Throttled.throttled_with(work.job)
          return false unless throttled

          Throttled.cooldown&.notify_throttled(work.queue)
          Throttled.requeue_throttled(work, strategies)
          true
        end
      end
    end
  end
end
