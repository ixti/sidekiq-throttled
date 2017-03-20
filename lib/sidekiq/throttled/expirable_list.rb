# frozen_string_literal: true

require "monitor"

module Sidekiq
  module Throttled
    # List that tracks when elements were added and enumerates over those not
    # older than `ttl` seconds ago.
    #
    # ## Implementation
    #
    # Internally list holds an array of arrays. Thus ecah element is a tuple of
    # timestamp (when element was added) and element itself:
    #
    #     [
    #       [ 1234567890.12345, "default" ],
    #       [ 1234567890.34567, "urgent" ],
    #       [ 1234579621.56789, "urgent" ],
    #       ...
    #     ]
    #
    # It does not deduplicates elements. Eviction happens only upon elements
    # retrieval (see {#each}).
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
        @mon.synchronize { @arr << [Time.now.to_f, element] }
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
          horizon = Time.now.to_f - @ttl

          # drop all elements older than horizon
          @arr.shift while @arr[0] && @arr[0][0] < horizon

          @arr.each { |x| yield x[1] }
        end

        self
      end
    end
  end
end
