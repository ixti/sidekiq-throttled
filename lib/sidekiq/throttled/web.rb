# frozen_string_literal: true

# stdlib
require "pathname"

# 3rd party
require "sidekiq"
require "sidekiq/web"

# internal
require "sidekiq/throttled/registry"
require "sidekiq/throttled/web/stats"

module Sidekiq
  module Throttled
    # Provides Sidekiq tab to monitor and reset throttled stats.
    #
    # @private
    module Web
      VIEWS         = Pathname.new(__dir__).join("web")
      THROTTLED_TPL = VIEWS.join("throttled.html.erb").read.freeze
      QUEUES_TPL    = VIEWS.join("queues.html.erb").read.freeze

      class << self
        # @api private
        def registered(app)
          register_throttled_tab app
          register_enhanced_queues_tab app
        end

        private

        def register_throttled_tab(app)
          app.get("/throttled") { erb THROTTLED_TPL.dup }

          app.delete("/throttled/:id") do
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
