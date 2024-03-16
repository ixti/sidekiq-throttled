# frozen_string_literal: true

module Sidekiq
  module Throttled
    class Message
      class << self
        def parse(message)
          new(Sidekiq.load_json(message))
        end
      end

      def initialize(item)
        @item = item
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
    end
  end
end
