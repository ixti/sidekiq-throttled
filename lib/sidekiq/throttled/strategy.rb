# frozen_string_literal: true

# internal
require "sidekiq/throttled/errors"
require "sidekiq/throttled/strategy/concurrency"
require "sidekiq/throttled/strategy/threshold"

module Sidekiq
  module Throttled
    # Meta-strategy that couples {Concurrency} and {Threshold} strategies.
    #
    # @private
    class Strategy
      # @!attribute [r] concurrency
      #   @return [Strategy::Concurrency, nil]
      attr_reader :concurrency

      # @!attribute [r] threshold
      #   @return [Strategy::Threshold, nil]
      attr_reader :threshold

      # @param [#to_s] name
      # @param [Hash] concurrency Concurrency options.
      #   See keyword args of {Strategy::Concurrency#initialize} for details.
      # @param [Hash] threshold Threshold options.
      #   See keyword args of {Strategy::Threshold#initialize} for details.
      # @param [#call] key_suffix Dynamic key suffix generator.
      def initialize(name, concurrency: nil, threshold: nil, key_suffix: nil)
        key = "throttled:#{name}"

        @concurrency =
          if concurrency
            concurrency[:key_suffix] ||= key_suffix
            Concurrency.new(key, **concurrency)
          end

        @threshold =
          if threshold
            threshold[:key_suffix] ||= key_suffix
            Threshold.new(key, **threshold)
          end

        return if @concurrency || @threshold

        raise ArgumentError, "Neither :concurrency nor :threshold given"
      end

      # @return [Boolean] whenever strategy has dynamic config
      def dynamic?
        return true if @concurrency&.dynamic?
        return true if @threshold&.dynamic?

        false
      end

      # @return [Boolean] whenever job is throttled or not.
      def throttled?(jid, *job_args)
        return true if @concurrency&.throttled?(jid, *job_args)

        if @threshold&.throttled?(*job_args)
          finalize!(jid, *job_args)
          return true
        end

        false
      end

      # Marks job as being processed.
      # @return [void]
      def finalize!(jid, *job_args)
        @concurrency&.finalize!(jid, *job_args)
      end

      # Resets count of jobs of all avaliable strategies
      # @return [void]
      def reset!
        @concurrency&.reset!
        @threshold&.reset!
      end
    end
  end
end
