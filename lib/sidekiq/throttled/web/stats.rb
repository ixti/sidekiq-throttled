module Sidekiq
  module Throttled
    module Web
      # Throttle strategy stats generation helper
      # @private
      class Stats
        TIME_CONVERSION = [
          [60 * 60 * 24,  "day",    "days"],
          [60 * 60,       "hour",   "hours"],
          [60,            "minute", "minutes"],
          [1,             "second", "seconds"]
        ].freeze

        # @param [Strategy::Concurrency, Strategy::Threshold] strategy
        def initialize(strategy)
          @strategy = strategy
        end

        # @return [String]
        def to_html
          return "" unless @strategy

          html = humanize_integer(@strategy.limit) << " jobs"

          if @strategy.respond_to? :period
            html << " per " << humanize_duration(@strategy.period)
          end

          html << "<br />" << colorize_count(@strategy.count, @strategy.limit)
        end

        private

        # @return [String]
        def colorize_count(int, max)
          percentile = 100.00 * int / max
          lvl = case
                when 80 <= percentile then "danger"
                when 60 <= percentile then "warning"
                else                       "success"
                end

          %(<span class="label label-#{lvl}">#{int}</span>)
        end

        # @return [String]
        def humanize_duration(int)
          arr = []

          TIME_CONVERSION.each do |(dimension, unit, units)|
            count = (int / dimension).to_i
            next unless 0 < count
            int -= count * dimension
            arr << "#{count} #{1 == count ? unit : units}"
          end

          arr.join " "
        end

        # @return [String]
        def humanize_integer(int)
          digits = int.to_s.split ""
          str    = digits.shift(digits.count % 3).join("")

          str << " " << digits.shift(3).join("") while 0 < digits.count

          str.strip
        end
      end
    end
  end
end
