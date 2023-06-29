# frozen_string_literal: true

module Sidekiq
  module Throttled
    # Configuration holder.
    class Configuration
      attr_reader :default_requeue_strategy

      # Class constructor.
      def initialize
        reset!
      end

      # Reset configuration to defaults.
      #
      # @return [self]
      def reset!
        @inherit_strategies = false
        @default_requeue_strategy = :enqueue

        self
      end

      # Instructs throttler to lookup strategies in parent classes, if there's
      # no own strategy:
      #
      #     class FooJob
      #       include Sidekiq::Job
      #       include Sidekiq::Throttled::Job
      #
      #       sidekiq_throttle :concurrency => { :limit => 42 }
      #     end
      #
      #     class BarJob < FooJob
      #     end
      #
      # By default in the example above, `Bar` won't have throttling options.
      # Set this flag to `true` to enable this lookup in initializer, after
      # that `Bar` will use `Foo` throttling bucket.
      def inherit_strategies=(value)
        @inherit_strategies = value ? true : false
      end

      # Whenever throttled workers should inherit parent's strategies or not.
      # Default: `false`.
      #
      # @return [Boolean]
      def inherit_strategies?
        @inherit_strategies
      end

      # Specifies how we should return throttled jobs to the queue so they can be executed later.
      # Options are `:enqueue` (put them on the end of the queue) and `:schedule` (schedule for later).
      # Default: `:enqueue`
      #
      def default_requeue_strategy=(value)
        @default_requeue_strategy = value.intern
      end
    end
  end
end
