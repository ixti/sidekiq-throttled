# frozen_string_literal: true

require "sidekiq"
require "sidekiq/fetch"

module Sidekiq
  module Throttled
    module Patches
      module BasicFetch
        class << self
          def apply!
            Sidekiq::BasicFetch.prepend(self) unless Sidekiq::BasicFetch.include?(self)
          end
        end

        # Retrieves job from redis.
        #
        # @return [Sidekiq::Throttled::UnitOfWork, nil]
        def retrieve_work
          work = super

          if work && Throttled.throttled?(work.job)
            Throttled.requeue_throttled(work)
            return nil
          end

          work
        end

        private

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
end
