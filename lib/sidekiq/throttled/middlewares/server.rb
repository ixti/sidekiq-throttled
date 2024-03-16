# frozen_string_literal: true

# internal
require_relative "../registry"

module Sidekiq
  module Throttled
    module Middlewares
      # Server middleware required for Sidekiq::Throttled functioning.
      class Server
        include Sidekiq::ServerMiddleware

        def call(_worker, msg, _queue)
          yield
        ensure
          job  = msg.fetch("wrapped") { msg["class"] }
          args = msg.key?("wrapped") ? msg.dig("args", 0, "arguments") : msg["args"]
          jid  = msg["jid"]

          if job && jid
            Registry.get job do |strategy|
              strategy.finalize!(jid, *args)
            end
          end
        end
      end
    end
  end
end
