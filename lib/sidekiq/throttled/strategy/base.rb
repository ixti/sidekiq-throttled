# frozen_string_literal: true

# rubocop:disable Security/Eval
begin
  require "redis_prescription"
rescue LoadError
  # Handle legacy redis-prescription 1.0
  require "redis/prescription"
  RedisPrescription = Redis::Prescription

  class RedisPrescription
    def call(redis, keys: [], argv: [])
      eval(redis, :keys => keys, :argv => argv)
    end
  end
end
# rubocop:enable Security/Eval

module Sidekiq
  module Throttled
    class Strategy
      module Base
        def limit(job_args = nil)
          @limit.respond_to?(:call) ? @limit.call(*job_args) : @limit
        end

        private

        def key(job_args)
          key = @base_key.dup
          return key unless @key_suffix

          key << ":#{@key_suffix.call(*job_args)}"
        rescue => e
          Sidekiq.logger.error "Failed to get key suffix: #{e}"
          raise e
        end
      end
    end
  end
end
