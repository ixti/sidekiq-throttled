# frozen_string_literal: true

require "sidekiq"

require_relative "./throttled_retriever"

module Sidekiq
  module Throttled
    module Patches
      module SuperFetch
        def self.prepended(base)
          base.prepend(ThrottledRetriever)
        end

        private

        # Calls SuperFetch UnitOfWork's requeue to remove the job from the
        # temporary queue and push job back to the head of the queue, so that
        # the job won't be tried immediately after it was requeued (in most cases).
        #
        # @note This is triggered when job is throttled.
        #
        # @return [void]
        def requeue_throttled(work)
          # SuperFetch UnitOfWork's requeue will remove it from the temporary
          # queue and then requeue it, so no acknowledgement call is needed.
          work.requeue
        end

        # Returns list of non-paused queues to try to fetch jobs from.
        #
        # @note It may return an empty array.
        # @return [Array<Array(String, String)>]
        def active_queues
          # Create a hash of throttled queues for fast lookup
          throttled_queues = Throttled.cooldown&.queues&.to_a&.to_h { [_1, true] }
          return super unless throttled_queues

          # Reject throttled queues from the list of active queues
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
