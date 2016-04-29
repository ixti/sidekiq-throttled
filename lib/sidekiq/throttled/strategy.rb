# frozen_string_literal: true
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

      # @param [#to_s] name
      # @param [Hash] concurrency Concurrency options.
      #   See {Strategy::Concurrency#initialize} for details.
      # @param [Hash] threshold Threshold options.
      #   See {Strategy::Threshold#initialize} for details.
      # @param [Hash] key_suffix Proc for dynamic keys.
      def initialize(name, concurrency: nil, threshold: nil, key_suffix: nil)
        key = "throttled:#{name}"

        @concurrency =
          if concurrency
            concurrency[:key_suffix] = key_suffix
            Concurrency.new(key, concurrency)
          end

        @threshold =
          if threshold
            threshold[:key_suffix] = key_suffix
            Threshold.new(key, threshold)
          end

        return if @concurrency || @threshold

        raise ArgumentError, "Neither :concurrency nor :threshold given"
      end

      def dynamic_keys?
        (@concurrency && @concurrency.dynamic_keys?) ||
          (@threshold && @threshold.dynamic_keys?)
      end

      def dynamic_limit?
        (@concurrency && @concurrency.dynamic_limit?) ||
          (@threshold && @threshold.dynamic_limit?)
      end

      # @return [Boolean] whenever job is throttled or not.
      def throttled?(jid, *job_args)
        return true if @concurrency && @concurrency.throttled?(jid, *job_args)

        if @threshold && @threshold.throttled?(*job_args)
          finalize!(jid, *job_args)
          return true
        end

        false
      end

      # Marks job as being processed.
      # @return [void]
      def finalize!(jid, *job_args)
        @concurrency && @concurrency.finalize!(jid, *job_args)
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
