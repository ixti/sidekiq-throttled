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
      PAUSER_TPL    = VIEWS.join("pauser.html.erb").read.freeze

      class << self
        def registered(app)
          register_throttled app
          register_pauser app
        end

        private

        def register_throttled(app)
          app.get("/throttled") { erb THROTTLED_TPL.dup }

          app.delete("/throttled/:id") do
            Registry.get(params[:id], &:reset!)
            redirect "#{root_path}throttled"
          end
        end

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def register_pauser(app)
          pauser = QueuesPauser.instance

          app.get("/pauser") do
            @queues = Sidekiq::Queue.all
            erb PAUSER_TPL.dup
          end

          app.post("/pauser/:queue") do
            if "pause" == params[:action]
              pauser.pause!(params[:queue])
            else
              pauser.resume!(params[:queue])
            end
            redirect "#{root_path}pauser"
          end
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
      end
    end
  end
end

Sidekiq::Web.register Sidekiq::Throttled::Web
Sidekiq::Web.tabs["Throttled"] = "throttled"
Sidekiq::Web.tabs["Pauser"] = "pauser"
