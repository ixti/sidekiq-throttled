# frozen_string_literal: true

source "https://rubygems.org"

gem "appraisal"
gem "rake"
gem "rspec"
gem "rubocop",             "~> 0.90.0", :require => false
gem "rubocop-performance", "~> 1.8.0",  :require => false
gem "rubocop-rspec",       "~> 1.43.2", :require => false
gem "sidekiq"

group :development do
  gem "byebug"
  gem "guard",         :require => false
  gem "guard-rspec",   :require => false
  gem "guard-rubocop", :require => false
end

group :test do
  gem "apparition"
  gem "capybara"
  gem "coveralls", :require => false
  gem "puma"
  gem "rack-test"
  gem "simplecov"
  gem "sinatra"
  gem "timecop"
end

# Specify your gem's dependencies in sidekiq-throttled.gemspec
gemspec
