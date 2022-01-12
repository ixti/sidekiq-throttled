# frozen_string_literal: true

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
