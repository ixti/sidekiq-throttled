# frozen_string_literal: true

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

      def initialize(options)
        @strictly_ordered_queues = (options[:strict] ? true : false)
        @queues = options[:queues].map { |q| "queue:#{q}" }
        @queues.uniq! if @strictly_ordered_queues
      end

      # @return [Sidekiq::BasicFetch::UnitOfWork, nil]
      def retrieve_work
        work = brpop
        return unless work

        work = UnitOfWork.new(*work)
        return work unless Throttled.throttled? work.job

        queue = "queue:#{work.queue_name}"

        Sidekiq.redis { |conn| conn.lpush(queue, work.job) }

        nil
      end

      private

      # Tries to pop pair of `queue` and job `message` out of sidekiq queue.
      # @return [Array<String, String>, nil]
      def brpop
        queues = (@strictly_ordered_queues ? @queues : @queues.shuffle.uniq)
        Sidekiq.redis { |conn| conn.brpop(*queues, TIMEOUT) }
      end
    end
  end
end
