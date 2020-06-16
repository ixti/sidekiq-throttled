# frozen_string_literal: true

require "monitor"

require "concurrent/utility/monotonic_time"

module Sidekiq
  module Throttled
    # List that tracks when elements were added and enumerates over those not
    # older than `ttl` seconds ago.
    #
    # ## Implementation
    #
    # Internally list holds an array of arrays. Thus each element is a tuple of
    # monotonic timestamp (when element was added) and element itself:
    #
    #     [
    #       [ 123456.7890, "default" ],
    #       [ 123456.7891, "urgent" ],
    #       [ 123457.9621, "urgent" ],
    #       ...
    #     ]
    #
    # It does not deduplicates elements. Eviction happens only upon elements
    # retrieval (see {#each}).
    #
    # @see http://ruby-concurrency.github.io/concurrent-ruby/Concurrent.html#monotonic_time-class_method
    # @see https://ruby-doc.org/core/Process.html#method-c-clock_gettime
    # @see https://linux.die.net/man/3/clock_gettime
    #
    # @private
    class ExpirableList
      include Enumerable

      # @param ttl [Float] elements time-to-live in seconds
      def initialize(ttl)
        @ttl = ttl.to_f
        @arr = []
        @mon = Monitor.new
      end

      # Pushes given element into the list.
      #
      # @params element [Object]
      # @return [ExpirableList] self
      def <<(element)
        @mon.synchronize { @arr << [Concurrent.monotonic_time, element] }
        self
      end

      # Evicts expired elements and calls the given block once for each element
      # left, passing that element as a parameter.
      #
      # @yield [element]
      # @return [Enumerator] if no block given
      # @return [ExpirableList] self if block given
      def each
        return to_enum __method__ unless block_given?

        @mon.synchronize do
          horizon = Concurrent.monotonic_time - @ttl

          # drop all elements older than horizon
          @arr.shift while @arr[0] && @arr[0][0] < horizon

          @arr.each { |x| yield x[1] }
        end

        self
      end
    end
  end
end
