# frozen_string_literal: true

require "pathname"

require "sidekiq"
require "sidekiq/web"

require_relative "./registry"
require_relative "./web/stats"

module Sidekiq
  module Throttled
    module Web
      ROOT  = Pathname.new(__dir__).join("../../../web").expand_path.realpath.freeze
      VIEWS = ROOT.join("views").freeze

      def self.registered(app)
        app.get("/throttled") do
          erb :index, views: VIEWS
        end

        app.post("/throttled/:id/reset") do
          Registry.get(route_params(:id), &:reset!)
          redirect "#{root_path}throttled"
        end
      end
    end
  end
end

Sidekiq::Web.configure do |config|
  config.register_extension(
    Sidekiq::Throttled::Web,
    name:     "throttled",
    tab:      %w[Throttled],
    index:    %w[throttled],
    root_dir: Sidekiq::Throttled::Web::ROOT.to_s
  )
end
