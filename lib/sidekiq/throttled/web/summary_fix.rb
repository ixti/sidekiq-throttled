# frozen_string_literal: true

module Sidekiq
  module Throttled
    module Web
      module SummaryFix
        HTML = File.read("#{__dir__}/summary_fix.html").freeze

        class << self
          attr_accessor :enabled

          def apply!(app)
            if "4.2.0" <= Sidekiq::VERSION
              Sidekiq::WebAction.send(:prepend, SummaryFix)
            else
              app.send(:prepend, SummaryFix)
            end
          end
        end

        def display_custom_head
          "#{super}#{HTML if SummaryFix.enabled}"
        end
      end
    end
  end
end
