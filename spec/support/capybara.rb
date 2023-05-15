# frozen_string_literal: true

require "capybara/rspec"

RSpec.configure do |config|
  config.before(type: :feature) { Capybara.app = Sidekiq::Web }
end
