# frozen_string_literal: true

module Sidekiq
  module Throttled
    module Web
      module SummaryFix
        JAVASCRIPT = [File.read(__FILE__.sub(/\.rb$/, ".js")).freeze].freeze
        HEADERS    = { "Content-Type" => "application/javascript" }.freeze

        class << self
          attr_accessor :enabled

          def apply!(app)
            Sidekiq::WebAction.prepend SummaryFix

            app.get("/throttled/summary_fix") do
              [200, HEADERS.dup, JAVASCRIPT.dup]
            end
          end
        end

        def display_custom_head
          "#{super}#{summary_fix_script if SummaryFix.enabled}"
        end

        private

        def summary_fix_script
          src = "#{root_path}throttled/summary_fix"
          %(<script type="text/javascript" src="#{src}"></script>)
        end
      end
    end
  end
end
