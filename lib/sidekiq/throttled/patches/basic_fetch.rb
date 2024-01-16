# frozen_string_literal: true

require "sidekiq"
require "sidekiq/fetch"

require_relative "./throttled_retriever"

module Sidekiq
  module Throttled
    module Patches
      module BasicFetch
        def self.prepended(base)
          base.prepend(ThrottledRetriever)
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
          throttled_queues = Throttled.cooldown&.queues
          return super unless throttled_queues&.size&.positive?

          super - throttled_queues
        end
      end
    end
  end
end

Sidekiq::BasicFetch.prepend(Sidekiq::Throttled::Patches::BasicFetch)
