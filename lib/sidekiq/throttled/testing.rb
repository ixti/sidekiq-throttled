# frozen_string_literal: true
require "sidekiq/throttled/registry"

RSpec.configure do |config|
  config.before :example do
    Sidekiq::Throttled::Registry.instance_eval do
      @strategies.clear
      @aliases.clear
    end
  end
end
