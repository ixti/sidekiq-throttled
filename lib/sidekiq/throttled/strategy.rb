# internal
require "sidekiq/throttled/errors"
require "sidekiq/throttled/strategy/concurrency"
require "sidekiq/throttled/strategy/threshold"

module Sidekiq
  module Throttled
    # Meta-strategy that couples {Concurrency} and {Threshold} strategies.
    class Strategy
      # @!attribute [r] concurrency
      #   @return [Strategy::Concurrency, nil]
      attr_reader :concurrency

      # @!attribute [r] threshold
      #   @return [Strategy::Threshold, nil]
      attr_reader :threshold

      # @param [#to_s] key
      # @param [Hash] concurrency Concurrency options.
      #   See {Strategy::Concurrency#initialize} for details.
      # @param [Hash] threshold Threshold options.
      #   See {Strategy::Threshold#initialize} for details.
      def initialize(key, concurrency: nil, threshold: nil)
        base_key      = "throttled:#{key}"

        @concurrency  = concurrency && Concurrency.new(base_key, concurrency)
        @threshold    = threshold && Threshold.new(base_key, threshold)

        return if @concurrency || @threshold

        raise ArgumentError, "Neither :concurrency nor :threshold given"
      end

      # @return [Boolean] whenever job is throttled or not.
      def throttled?(jid)
        return true if @concurrency && @concurrency.throttled?(jid)

        if @threshold && @threshold.throttled?
          finalize! jid
          return true
        end

        false
      end

      # Marks job as being processed.
      # @return [void]
      def finalize!(jid)
        @concurrency && @concurrency.finalize!(jid)
      end

      # Resets count of jobs of all avaliable strategies
      # @return [void]
      def reset!
        @concurrency && @concurrency.reset!
        @threshold && @threshold.reset!
      end
    end
  end
end
