# frozen_string_literal: true

# stdlib
require "pathname"
require "rubygems"

# 3rd party
require "sidekiq"
require "sidekiq/web"

# internal
require_relative "./registry"
require_relative "./web/stats"

module Sidekiq
  module Throttled
    # Provides Sidekiq tab to monitor and reset throttled stats.
    module Web
      VIEWS         = Pathname.new(__dir__).join("web")
      THROTTLED_TPL = VIEWS.join("throttled.html.erb").read.freeze

      class << self
        # @api private
        def registered(app)
          register_throttled_tab app
        end

        private

        def register_throttled_tab(app)
          app.get("/throttled") { erb THROTTLED_TPL.dup }

          app.post("/throttled/:id/reset") do
            Registry.get(params[:id], &:reset!)
            redirect "#{root_path}throttled"
          end
        end
      end
    end
  end
end

sidekiq_version = Gem::Version.new(Sidekiq::VERSION)
if sidekiq_version >= Gem::Version.new("8.0.0")
  Sidekiq::Web.configure do |config|
    config.register_extension(Sidekiq::Throttled::Web,
      name:  "throttled",
      tab:   ["Throttled"],
      index: ["throttled"])
  end
else
  Sidekiq::Web.register Sidekiq::Throttled::Web
  Sidekiq::Web.tabs["Throttled"] = "throttled"
end
