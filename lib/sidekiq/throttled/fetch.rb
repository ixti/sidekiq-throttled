# frozen_string_literal: true

require "sidekiq"
require "sidekiq/throttled/unit_of_work"

module Sidekiq
  module Throttled
    # Throttled fetch strategy.
    class Fetch
      TIMEOUT = 2
      private_constant :TIMEOUT

      def initialize(options)
        @strictly_ordered_queues = options[:strict]
        @queues = options[:queues].map { |q| "queue:#{q}" }
        @queues.uniq! if @strictly_ordered_queues
      end

      # @return [Sidekiq::Throttled::UnitOfWork, nil]
      def retrieve_work
        work = brpop
        return unless work

        work = UnitOfWork.new(*work)
        return work unless Throttled.throttled? work.job

        Sidekiq.redis do |conn|
          conn.lpush("queue:#{work.queue_name}", work.job)
        end

        nil
      end

      private

      # Tries to pop pair of `queue` and job `message` out of sidekiq queue.
      # @return [Array<String, String>, nil]
      def brpop
        Sidekiq.redis { |conn| conn.brpop(*queues, TIMEOUT) }
      end

      def queues
        (@strictly_ordered_queues ? @queues : @queues.shuffle.uniq)
      end
    end
  end
end
