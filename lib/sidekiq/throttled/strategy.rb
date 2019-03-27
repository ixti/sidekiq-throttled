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

      # @!attribute [r] observe
      #   @return [Proc, nil]
      attr_reader :observe

      # @param [#to_s] name
      # @param [Hash] concurrency Concurrency options.
      #   See keyword args of {Strategy::Concurrency#initialize} for details.
      # @param [Hash] threshold Threshold options.
      #   See keyword args of {Strategy::Threshold#initialize} for details.
      # @param [#call] key_suffix Dynamic key suffix generator.
      # @param [#call] observe Process called after throttled.
      def initialize(name, concurrency: nil, threshold: nil, key_suffix: nil,
        observe: nil)
        @observe = observe

        key = "throttled:#{name}"

        @concurrency = initialize_of(:concurrency, key, key_suffix, concurrency)
        @threshold   = initialize_of(:threshold, key, key_suffix, threshold)

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
        if @concurrency&.throttled?(jid, *job_args)
          @observe&.call(:concurrency, *job_args)
          return true
        end

        if @threshold&.throttled?(*job_args)
          @observe&.call(:threshold, *job_args)
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

      private

      def initialize_of(name, key, key_suffix, hash)
        return nil unless hash
        hash[:key_suffix] ||= key_suffix
        Strategy.const_get(name.to_s.capitalize).new(key, **hash)
      end
    end
  end
end
