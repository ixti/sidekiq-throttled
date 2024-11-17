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

        # Returns list of queues to try to fetch jobs from.
        #
        # @note It may return an empty array.
        # @param [Array<String>] queues
        # @return [Array<String>]
        def queues_cmd
          throttled_queues = Throttled.cooldown&.queues
          return super if throttled_queues.nil? || throttled_queues.empty?

          super - throttled_queues
        end
      end
    end
  end
end

Sidekiq::BasicFetch.prepend(Sidekiq::Throttled::Patches::BasicFetch)
