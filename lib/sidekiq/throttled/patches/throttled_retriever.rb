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

          if work && Throttled.throttled?(work.job)
            Throttled.cooldown&.notify_throttled(work.queue)
            requeue_throttled(work)
            return nil
          end

          Throttled.cooldown&.notify_admitted(work.queue) if work

          work
        end
      end
    end
  end
end
