# frozen_string_literal: true

# internal
module Sidekiq
  module Throttled
    # Collection which transparently group several meta-strategies of one kind
    #
    # @private
    class StrategyCollection
      include Enumerable

      attr_reader :strategies

      # @param [Hash, Array, nil] strategies Concurrency or Threshold options
      #   or array of options.
      #   See keyword args of {Strategy::Concurrency#initialize} for details.
      #   See keyword args of {Strategy::Threshold#initialize} for details.
      # @param [Class] strategy class of strategy: Concurrency or Threshold
      # @param [#to_s] name
      # @param [#call] key_suffix Dynamic key suffix generator.
      def initialize(strategies, strategy:, name:, key_suffix:)
        @strategies = (strategies.is_a?(Hash) ? [strategies] : Array(strategies)).map do |options|
          make_strategy(strategy, name, key_suffix, options)
        end
      end

      # @param [#call] block
      # Iterates each strategy in collection
      def each(...)
        @strategies.each(...)
      end

      # @return [Boolean] whenever any strategy in collection has dynamic config
      def dynamic?
        any?(&:dynamic?)
      end

      # @return [Boolean] whenever job is throttled or not
      # by any strategy in collection.
      def throttled?(...)
        any? { |s| s.throttled?(...) }
      end

      # Marks job as being processed.
      # @return [void]
      def finalize!(...)
        each { |c| c.finalize!(...) }
      end

      # Resets count of jobs of all avaliable strategies
      # @return [void]
      def reset!
        each(&:reset!)
      end

      private

      # @return [Base, nil]
      def make_strategy(strategy, name, key_suffix, options)
        return unless options

        strategy.new("throttled:#{name}",
          key_suffix: key_suffix,
          **options)
      end
    end
  end
end
