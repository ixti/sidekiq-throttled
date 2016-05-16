# frozen_string_literal: true
# stdlib
require "thread"

# 3rd party
require "celluloid" if Sidekiq::VERSION < "4.0.0"
require "sidekiq"
require "sidekiq/fetch"

module Sidekiq
  module Throttled
    # Throttled version of `Sidekiq::BasicFetch` fetcher strategy.
    class BasicFetch < ::Sidekiq::BasicFetch
      TIMEOUT = 2

      class UnitOfWork < ::Sidekiq::BasicFetch::UnitOfWork
        alias job message if Sidekiq::VERSION < "4.0.0"
      end

      # Class constructor
      def initialize(*args)
        @mutex      = Mutex.new
        @suspended  = []

        super(*args)
      end

      # @return [Sidekiq::BasicFetch::UnitOfWork, nil]
      def retrieve_work
        work = brpop
        return unless work

        work = UnitOfWork.new(*work)
        return work unless Throttled.throttled? work.job

        queue = "queue:#{work.queue_name}"

        @mutex.synchronize { @suspended << queue }
        Sidekiq.redis { |conn| conn.lpush(queue, work.job) }

        nil
      end

      private

      # Tries to pop pair of `queue` and job `message` out of sidekiq queue.
      # @return [Array<String, String>, nil]
      def brpop
        queues = if @strictly_ordered_queues
                   # seems latest sidekiq doesnt use unique_queues anymore
                   @unique_queues.try(:dup) || @queues
                 else
                   @queues.shuffle.uniq
                 end

        @mutex.synchronize do
          next if @suspended.empty?
          queues -= @suspended
          @suspended.clear
        end

        if queues.empty?
          sleep TIMEOUT
          return
        end

        Sidekiq.redis { |conn| conn.brpop(*queues, TIMEOUT) }
      end
    end
  end
end
