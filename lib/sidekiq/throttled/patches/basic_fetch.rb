# frozen_string_literal: true

require "sidekiq"
require "sidekiq/fetch"
require "sidekiq/throttled/expirable_list"

module Sidekiq
  module Throttled
    module Patches
      module BasicFetch
        class << self
          def apply!
            Sidekiq::BasicFetch.prepend(self) unless Sidekiq::BasicFetch.include?(self)
          end
        end

        # Timeout to sleep between fetch retries once at least
        # timeout_after_attempts worth of throttled jobs are hit on a single
        # queue. These balance scanning through a single queue for unthrottled
        # jobs and not allowing lower priority queues to be completely starved
        # by throttled jobs in higher queues
        TIMEOUT_AFTER_ATTEMPTS = 100
        TIMEOUT = 1

        def initialize(cap)
          super

          sidekiq_version = Gem::Version.new(Sidekiq::VERSION)
          if sidekiq_version < Gem::Version.new("7.0.0")
            @throttled_queue_cooldown = config.fetch(:throttled_queue_cooldown, TIMEOUT)
            @throttled_queue_after_attempts = config.fetch(:throttled_queue_after_attempts, TIMEOUT_AFTER_ATTEMPTS)
          else
            @throttled_queue_cooldown = config.lookup(:throttled_queue_cooldown) || TIMEOUT
            @throttled_queue_after_attempts = config.lookup(:throttled_queue_after_attempts) || TIMEOUT_AFTER_ATTEMPTS
          end

          @paused = ExpirableList.new(@throttled_queue_cooldown)
        end

        # Retrieves job from redis.
        #
        # @return [Sidekiq::Throttled::UnitOfWork, nil]
        def retrieve_work
          work = super

          if work && Throttled.throttled?(work.job)
            requeue_throttled(work)

            if @last_throttled_queue == work.queue_name
              @last_throttled_count += 1
            else
              @last_throttled_queue = work.queue_name
              @last_throttled_count = 1
            end

            if @last_throttled_count >= @throttled_queue_after_attempts
              @paused << work.queue_name
              @last_throttled_queue = nil
              @last_throttled_count = 0
            end

            return nil
          end

          @last_throttled_queue = nil
          @last_throttled_count = 0

          work
        end

        private

        # Pushes job back to the head of the queue, so that job won't be tried
        # immediately after it was requeued (in most cases).
        #
        # @note This is triggered when job is throttled. So it is same operation
        #   Sidekiq performs upon `Sidekiq::Worker.perform_async` call.
        #
        # @return [void]
        def requeue_throttled(work)
          redis { |conn| conn.lpush(work.queue, work.job) }
        end

        # Returns list of queues to try to fetch jobs from.
        #
        # @note It may return an empty array.
        # @param [Array<String>] queues
        # @return [Array<String>]
        def queues_cmd
          queues = super

          # TODO: Refactor to be prepended as an integration mixin during configuration stage
          #   Or via configurable queues reducer
          queues -= Sidekiq::Pauzer.paused_queues.map { |name| "queue:#{name}" } if defined?(Sidekiq::Pauzer)

          queues -= @paused.to_a

          queues
        end
      end
    end
  end
end
