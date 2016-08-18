# frozen_string_literal: true

require "sidekiq"

module Sidekiq
  module Throttled
    class UnitOfWork
      QUEUE_NAME_PREFIX_RE = /^.*queue:/
      private_constant :QUEUE_NAME_PREFIX_RE

      attr_reader :queue

      attr_reader :job

      def initialize(queue, job)
        @queue = queue
        @job   = job
      end

      def acknowledge
        # do nothing
      end

      def queue_name
        queue.sub(QUEUE_NAME_PREFIX_RE, "")
      end

      def requeue
        Sidekiq.redis { |conn| conn.rpush("queue:#{queue_name}", job) }
      end
    end
  end
end
