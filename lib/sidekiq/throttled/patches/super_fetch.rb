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

        # Returns list of non-paused queues to try to fetch jobs from.
        #
        # @note It may return an empty array.
        # @return [Array<Array(String, String)>]
        def active_queues
          # Create a hash of throttled queues for fast lookup
          throttled_queues = Throttled.cooldown&.queues&.to_h { |queue| [queue, true] }
          return super if throttled_queues.nil? || throttled_queues.empty?

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
