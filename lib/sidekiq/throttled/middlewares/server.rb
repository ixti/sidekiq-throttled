# frozen_string_literal: true

# internal
require_relative "../message"
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
          finalize_strategies(msg)
        end

        private

        def finalize_strategies(msg)
          message = Message.new(msg)
          return unless message.job_class && message.job_id

          job_args = Array(message.job_args)
          Sidekiq::Throttled.strategy_keys_for(message).uniq.each do |key|
            Registry.get(key) do |strategy|
              strategy.finalize!(message.job_id, *job_args)
            end
          end
        end
      end
    end
  end
end
