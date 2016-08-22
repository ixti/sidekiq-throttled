# frozen_string_literal: true

source "https://rubygems.org"

gem "appraisal"
gem "rake"
gem "rspec"
gem "rubocop", "~> 0.42.0", :require => false

group :test do
  gem "coveralls"
  gem "rack-test"
  gem "simplecov", ">= 0.9"
  gem "sinatra", "~> 1.4", ">= 1.4.6"
  gem "timecop"
end

# Specify your gem's dependencies in sidekiq-throttled.gemspec
gemspec
