# frozen_string_literal: true

require "capybara/rspec"
require "capybara/poltergeist"

Capybara.javascript_driver = :poltergeist

RSpec.configure do |config|
  config.before(:type => :feature) { Capybara.app = Sidekiq::Web }
end
