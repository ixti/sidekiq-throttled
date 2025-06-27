# frozen_string_literal: true

require "concurrent"

require_relative "./expirable_set"

module Sidekiq
  module Throttled
    # @api internal
    #
    # Queues cooldown manager. Tracks list of queues that should be temporarily
    # (for the duration of {Config#cooldown_period}) excluded from polling.
    class Cooldown
      class << self
        # Returns new {Cooldown} instance if {Config#cooldown_period} is not `nil`.
        #
        # @param config [Config]
        # @return [Cooldown, nil]
        def [](config)
          new(config) if config.cooldown_period
        end
      end

      # @param config [Config]
      def initialize(config)
        @queues    = ExpirableSet.new
        @tracker   = Concurrent::Map.new
        @period    = config.cooldown_period
        @threshold = config.cooldown_threshold
      end

      # Notify that given queue returned job that was throttled.
      #
      # @param queue [String]
      # @return [void]
      def notify_throttled(queue)
        @queues.add(queue, ttl: @period) if @threshold <= @tracker.merge_pair(queue, 1, &:succ)
      end

      # Notify that given queue returned job that was not throttled.
      #
      # @param queue [String]
      # @return [void]
      def notify_admitted(queue)
        @tracker.delete(queue)
      end

      # List of queues that should not be polled
      #
      # @return [Array<String>]
      def queues
        @queues.to_a
      end
    end
  end
end
