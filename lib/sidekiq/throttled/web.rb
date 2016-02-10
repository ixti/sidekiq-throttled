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
    # @private
    module Web
      class << self
        def registered(app)
          template = Pathname.new(__FILE__).join("../web/index.html.erb").read
          app.get("/throttled") { erb template.dup }

          app.delete("/throttled/:id") do
            Registry.get(params[:id], &:reset!)
            redirect "#{root_path}throttled"
          end
        end
      end
    end
  end
end

Sidekiq::Web.register Sidekiq::Throttled::Web
Sidekiq::Web.tabs["Throttled"] = "throttled"
