# frozen_string_literal: true

module Sidekiq
  module Throttled
    module Web
      module SummaryFix
        HTML = File.read("#{__dir__}/summary_fix.html").freeze

        class << self
          attr_accessor :enabled
        end

        def display_custom_head
          SummaryFix.enabled ? "#{super}#{HTML}" : super
        end
      end
    end
  end
end
