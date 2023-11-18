# frozen_string_literal: true

module Sidekiq
  module Throttled
    # Configuration object.
    class Config
      # Period in seconds to exclude queue from polling in case it returned
      # {#cooldown_threshold} amount of throttled jobs in a row.
      #
      # Set this to `nil` to disable cooldown completely.
      #
      # @return [Float, nil]
      attr_reader :cooldown_period

      # Amount of throttled jobs returned from the queue subsequently after
      # which queue will be excluded from polling for the durations of
      # {#cooldown_period}.
      #
      # @return [Integer]
      attr_reader :cooldown_threshold

      def initialize
        @cooldown_period    = 2.0
        @cooldown_threshold = 1
      end

      # @!attribute [w] cooldown_period
      def cooldown_period=(value)
        raise TypeError, "unexpected type #{value.class}" unless value.nil? || value.is_a?(Float)
        raise ArgumentError, "period must be positive"    unless value.nil? || value.positive?

        @cooldown_period = value
      end

      # @!attribute [w] cooldown_threshold
      def cooldown_threshold=(value)
        raise TypeError, "unexpected type #{value.class}" unless value.is_a?(Integer)
        raise ArgumentError, "threshold must be positive" unless value.positive?

        @cooldown_threshold = value
      end
    end
  end
end
