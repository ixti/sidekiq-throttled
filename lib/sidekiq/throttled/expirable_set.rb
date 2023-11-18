# frozen_string_literal: true

require "concurrent"

module Sidekiq
  module Throttled
    # @api internal
    #
    # Set of elements with expirations.
    #
    # @example
    #   set = ExpirableSet.new(10.0)
    #   set.add("a")
    #   sleep(5)
    #   set.add("b")
    #   set.to_a # => ["a", "b"]
    #   sleep(5)
    #   set.to_a # => ["b"]
    class ExpirableSet
      include Enumerable

      # @param ttl [Float] expiration is seconds
      # @raise [ArgumentError] if `ttl` is not positive Float
      def initialize(ttl)
        raise ArgumentError, "ttl must be positive Float" unless ttl.is_a?(Float) && ttl.positive?

        @elements = Concurrent::Map.new
        @ttl      = ttl
      end

      # @param element [Object]
      # @return [ExpirableSet] self
      def add(element)
        # cleanup expired elements to avoid mem-leak
        horizon = now
        expired = @elements.each_pair.select { |(_, sunset)| expired?(sunset, horizon) }
        expired.each { |pair| @elements.delete_pair(*pair) }

        # add new element
        @elements[element] = now + @ttl

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
