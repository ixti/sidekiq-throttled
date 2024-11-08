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

      # Specifies how we should return throttled jobs to the queue so they can be executed later.
      # Expects a hash with keys that may include :with and :to
      # For :with, options are `:enqueue` (put them on the end of the queue) and `:schedule` (schedule for later).
      # For :to, the name of a sidekiq queue should be specified. If none is specified, jobs will by default be
      # requeued to the same queue they were originally enqueued in.
      # Default: {with: `:enqueue`}
      #
      # @return [Hash]
      attr_reader :default_requeue_options

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

      # @!attribute [w] default_requeue_options
      def default_requeue_options=(options)
        requeue_with = options.delete(:with).intern || :enqueue

        @default_requeue_options = options.merge({ with: requeue_with })
      end
    end
  end
end
