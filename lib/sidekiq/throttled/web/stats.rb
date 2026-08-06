# frozen_string_literal: true

module Sidekiq
  module Throttled
    module Web
      # Throttle strategy stats generation helper
      class Stats
        TIME_CONVERSION = [
          [60 * 60 * 24,  "day",    "days"],
          [60 * 60,       "hour",   "hours"],
          [60,            "minute", "minutes"],
          [1,             "second", "seconds"]
        ].freeze

        def self.fetch_registry
          strategies = Registry.each_with_static_keys.to_a
          throttle_components = strategies.flat_map do |_name, strategy|
            strategy.concurrency.to_a + strategy.threshold.to_a
          end

          [strategies, fetch_counts(throttle_components)]
        end

        def self.fetch_counts(strategies)
          strategies = strategies.compact
          return {} if strategies.empty?

          counts = Sidekiq.redis do |redis|
            redis.pipelined do |pipeline|
              strategies.each { |strategy| strategy.count_from(pipeline) }
            end
          end

          strategies.zip(counts.map(&:to_i)).to_h
        end

        # @param [Strategy::Concurrency, Strategy::Threshold] strategy
        def initialize(strategy, count: nil)
          raise ArgumentError, "Can't handle dynamic strategies" if strategy&.dynamic?

          @strategy = strategy
          @count = count
        end

        # @return [String]
        def to_html
          return "" unless @strategy

          html = humanize_integer(@strategy.limit) << " jobs"

          html << " per " << humanize_duration(@strategy.period) if @strategy.respond_to?(:period)

          count = @count.nil? ? @strategy.count : @count
          html << "<br />" << colorize_count(count, @strategy.limit)
        end

        private

        # @return [String]
        def colorize_count(int, max)
          percentile = 100.00 * int / max
          lvl = if    80 <= percentile then "danger"
                elsif 60 <= percentile then "warning"
                else
                  "success"
                end

          %(<span class="label label-#{lvl}">#{int}</span>)
        end

        # @return [String]
        def humanize_duration(int)
          arr = []

          TIME_CONVERSION.each do |(dimension, unit, units)|
            count = (int / dimension).to_i

            next unless count.positive?

            int -= count * dimension
            arr << "#{count} #{1 == count ? unit : units}"
          end

          arr.join " "
        end

        # @return [String]
        def humanize_integer(int)
          int.to_s.chars
            .reverse
            .each_slice(3)
            .map(&:reverse)
            .reverse
            .map(&:join)
            .join(",")
        end
      end
    end
  end
end
