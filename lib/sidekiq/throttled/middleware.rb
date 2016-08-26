# frozen_string_literal: true
# internal
require "sidekiq/throttled/registry"

module Sidekiq
  module Throttled
    # Server middleware that notifies strategy that job was finished.
    #
    # @private
    class Middleware
      # Called within Sidekiq job processing
      def call(_worker, msg, _queue)
        yield
      ensure
        Registry.get msg["class".freeze] do |strategy|
          strategy.finalize!(msg["jid".freeze], *msg["args"])
        end
      end
    end
  end
end
