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
          key << ":#{@key_suffix.call(*job_args)}" if @key_suffix
          key
        end
      end
    end
  end
end
