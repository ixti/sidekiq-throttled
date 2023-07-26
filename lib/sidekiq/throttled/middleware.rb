# frozen_string_literal: true

# internal
require_relative "./registry"

module Sidekiq
  module Throttled
    # Server middleware that notifies strategy that job was finished.
    #
    # @private
    class Middleware
      include Sidekiq::ServerMiddleware if Sidekiq::VERSION >= "6.5.0"

      # Called within Sidekiq job processing
      def call(_worker, msg, _queue)
        yield
      ensure
        job = msg.fetch("wrapped") { msg.fetch("class", false) }
        jid = msg.fetch("jid", false)

        if job && jid
          Registry.get job do |strategy|
            strategy.finalize!(jid, *msg["args"])
          end
        end
      end
    end
  end
end
