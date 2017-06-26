# frozen_string_literal: true

# stdlib
require "pathname"

# 3rd party
require "sidekiq"
require "sidekiq/web"

# internal
require "sidekiq/throttled/registry"
require "sidekiq/throttled/web/stats"
require "sidekiq/throttled/web/summary_fix"

module Sidekiq
  module Throttled
    # Provides Sidekiq tab to monitor and reset throttled stats.
    module Web
      VIEWS         = Pathname.new(__dir__).join("web")
      THROTTLED_TPL = VIEWS.join("throttled.html.erb").read.freeze
      QUEUES_TPL    = VIEWS.join("queues.html.erb").read.freeze

      class << self
        # Replace default Queues tab with enhanced one.
        def enhance_queues_tab!
          SummaryFix.enabled = true
          Sidekiq::Web::DEFAULT_TABS["Queues"] = "enhanced-queues"
          Sidekiq::Web.tabs.delete("Enhanced Queues")
        end

        # Restore original Queues tab.
        #
        # @api There's next to absolutely no value in this method for real
        #   users. The only it's purpose is to restore virgin state in specs.
        def restore_queues_tab!
          SummaryFix.enabled = false
          Sidekiq::Web::DEFAULT_TABS["Queues"] = "queues"
          Sidekiq::Web.tabs["Enhanced Queues"] = "enhanced-queues"
        end

        # @api private
        def registered(app)
          SummaryFix.apply! app
          register_throttled_tab app
          register_enhanced_queues_tab app
        end

        private

        def register_throttled_tab(app)
          app.get("/throttled") { erb THROTTLED_TPL.dup }

          app.post("/throttled/:id/reset") do
            Registry.get(params[:id], &:reset!)
            redirect "#{root_path}throttled"
          end
        end

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def register_enhanced_queues_tab(app)
          pauser = QueuesPauser.instance

          app.get("/enhanced-queues") do
            @queues = Sidekiq::Queue.all
            erb QUEUES_TPL.dup
          end

          app.post("/enhanced-queues/:name") do
            case params[:action]
            when "delete" then Sidekiq::Queue.new(params[:name]).clear
            when "pause"  then pauser.pause!(params[:name])
            else               pauser.resume!(params[:name])
            end

            redirect "#{root_path}enhanced-queues"
          end
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
      end
    end
  end
end

Sidekiq::Web.register Sidekiq::Throttled::Web
Sidekiq::Web.tabs["Throttled"] = "throttled"
Sidekiq::Web.tabs["Enhanced Queues"] = "enhanced-queues"
