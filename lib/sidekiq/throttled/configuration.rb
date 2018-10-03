# frozen_string_literal: true

module Sidekiq
  module Throttled
    # Configuration holder.
    class Configuration
      # Class constructor.
      def initialize
        reset!
      end

      # Reset configuration to defaults.
      #
      # @return [void]
      def reset!
        @inherit_strategies = false
      end

      # Instructs throttler to lookup strategies in parent classes, if there's
      # no own strategy:
      #
      #     class Foo
      #       include Sidekiq::Worker
      #       include Sidekiq::Worker::Throttled
      #
      #       sidekiq_throttle :concurrency => { :limit => 42 }
      #     end
      #
      #     class Bar < Foo
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
    end
  end
end
