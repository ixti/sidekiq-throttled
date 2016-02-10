# stdlib
require "thread"

# 3rd party
require "celluloid"
require "sidekiq"
require "sidekiq/fetch"

module Sidekiq
  module Throttled
    # Throttled version of `Sidekiq::BasicFetch` fetcher strategy.
    class BasicFetch < ::Sidekiq::BasicFetch
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

        work = ::Sidekiq::BasicFetch::UnitOfWork.new(*work)
        return work unless Throttled.throttled? work.message

        queue = "queue:#{work.queue_name}"

        @mutex.synchronize { @suspended << queue }
        Sidekiq.redis { |conn| conn.lpush(queue, work.message) }

        nil
      end

      private

      # Tries to pop pair of `queue` and job `message` out of sidekiq queue.
      # @return [Array<String, String>, nil]
      def brpop
        queues = if @strictly_ordered_queues
                   @unique_queues.dup
                 else
                   @queues.shuffle.uniq
                 end

        @mutex.synchronize do
          next if @suspended.empty?
          queues -= @suspended
          @suspended.clear
        end

        if queues.empty?
          sleep Sidekiq::Fetcher::TIMEOUT
          return
        end

        Sidekiq.redis { |conn| conn.brpop(*queues, Sidekiq::Fetcher::TIMEOUT) }
      end
    end
  end
end
