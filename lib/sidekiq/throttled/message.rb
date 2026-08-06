# frozen_string_literal: true

module Sidekiq
  module Throttled
    class Message
      def initialize(item)
        @item = item.is_a?(Hash) ? item : parse(item)
      end

      def job_class
        @item.fetch("wrapped") { @item["class"] }
      end

      def job_args
        @item.key?("wrapped") ? @item.dig("args", 0, "arguments") : @item["args"]
      end

      def job_id
        @item["jid"]
      end

      def strategy_keys
        keys = @item["throttled_strategy_keys"] || @item["throttled_strategy_key"]

        Array(keys).compact.map(&:to_s)
      end

      private

      def parse(item)
        item = Sidekiq.load_json(item)
        item.is_a?(Hash) ? item : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
