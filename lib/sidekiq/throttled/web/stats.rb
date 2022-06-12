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

        # @param [Strategy::Concurrency, Strategy::Threshold] strategy
        def initialize(strategy)
          raise ArgumentError, "Can't handle dynamic strategies" if strategy&.dynamic?

          @strategy = strategy
        end

        # @return [String]
        def to_html
          return "" unless @strategy

          html = humanize_integer(@strategy.limit) << " jobs"

          html << " per " << humanize_duration(@strategy.period) if @strategy.respond_to?(:period)

          html << "<br />" << colorize_count(@strategy.count, @strategy.limit)
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
          digits = int.to_s.chars
          str    = digits.shift(digits.count % 3).join

          str << " " << digits.shift(3).join while digits.count.positive?

          str.strip
        end
      end
    end
  end
end
