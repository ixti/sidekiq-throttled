# frozen_string_literal: true

require "concurrent"

module Sidekiq
  module Throttled
    # @api internal
    #
    # Set of elements with expirations.
    #
    # @example
    #   set = ExpirableSet.new
    #   set.add("a", ttl: 10.0)
    #   sleep(5)
    #   set.add("b", ttl: 10.0)
    #   set.to_a # => ["a", "b"]
    #   sleep(5)
    #   set.to_a # => ["b"]
    class ExpirableSet
      include Enumerable

      def initialize
        @elements = Concurrent::Map.new
      end

      # @param element [Object]
      # @param ttl [Float] expiration is seconds
      # @raise [ArgumentError] if `ttl` is not positive Float
      # @return [ExpirableSet] self
      def add(element, ttl:)
        raise ArgumentError, "ttl must be positive Float" unless ttl.is_a?(Float) && ttl.positive?

        horizon = now

        # Cleanup expired elements
        expired = @elements.each_pair.select { |(_, sunset)| expired?(sunset, horizon) }
        expired.each { |pair| @elements.delete_pair(*pair) }

        # Add or update an element
        sunset = horizon + ttl
        @elements.merge_pair(element, sunset) { |old_sunset| [old_sunset, sunset].max }

        self
      end

      # @yield [Object] Gives each live (not expired) element to the block
      def each
        return to_enum __method__ unless block_given?

        horizon = now

        @elements.each_pair do |element, sunset|
          yield element unless expired?(sunset, horizon)
        end

        self
      end

      private

      # @return [Float]
      def now
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end

      def expired?(sunset, horizon)
        sunset <= horizon
      end
    end
  end
end
