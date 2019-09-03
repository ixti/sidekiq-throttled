# frozen_string_literal: true

require "capybara/rspec"
require "capybara/apparition"

Capybara.javascript_driver = :apparition

RSpec.configure do |config|
  config.before(:type => :feature) { Capybara.app = Sidekiq::Web }
end
