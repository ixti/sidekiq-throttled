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

          if work
            throttled, strategies = Throttled.throttled_with(work.job)

            if throttled
              Throttled.cooldown&.notify_throttled(work.queue)
              Throttled.requeue_throttled(work, strategies)
              return nil
            end
          end

          Throttled.cooldown&.notify_admitted(work.queue) if work

          work
        end
      end
    end
  end
end
