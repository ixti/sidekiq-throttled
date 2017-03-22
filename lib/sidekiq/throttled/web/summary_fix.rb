# frozen_string_literal: true

module Sidekiq
  module Throttled
    module Web
      module SummaryFix
        JAVASCRIPT = <<-JAVASCRIPT
        <script>
          $(function ($el) {
            var $el = $(".summary li.enqueued > a"),
                url = $el.attr("href").replace(/\/queues$/, "/enhanced-queues");
            $el.attr("href", url);
          });
        </script>
        JAVASCRIPT

        class << self
          attr_accessor :enabled
        end

        def display_custom_head
          SummaryFix.enabled ? "#{super}#{JAVASCRIPT}" : super
        end
      end
    end
  end
end
