# frozen_string_literal: true

SimpleCov.start do
  gemfile = File.basename(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"), ".gemfile").strip
  gemfile = nil if gemfile.empty? || gemfile.casecmp?("gems.rb") || gemfile.casecmp?("Gemfile")

  command_name ["#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}", gemfile].compact.join("/")

  enable_coverage :branch

  if ENV["CI"]
    require "simplecov-cobertura"
    formatter SimpleCov::Formatter::CoberturaFormatter
  else
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::SimpleFormatter,
      SimpleCov::Formatter::HTMLFormatter
    ])
  end

  add_filter "/demo/"
  add_filter "/gemfiles/"
  add_filter "/spec/"
  add_filter "/vendor/"
end
