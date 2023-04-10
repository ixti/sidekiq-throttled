# frozen_string_literal: true

source "https://rubygems.org"

gem "appraisal"
gem "rake"
gem "sidekiq"

group :test do
  gem "apparition"
  gem "capybara"
  gem "puma"
  gem "rack-test"
  gem "sinatra"

  gem "rspec"
  gem "timecop"

  gem "rubocop",              require: false
  gem "rubocop-performance",  require: false
  gem "rubocop-rake",         require: false
  gem "rubocop-rspec",        require: false
end

group :development, optional: true do
  gem "debug"
  gem "guard"
  gem "guard-rspec"
end

group :doc, optional: true do
  gem "asciidoctor"
  gem "yard"
end

gemspec
