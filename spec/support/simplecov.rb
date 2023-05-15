# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  command_name "BUNDLE_GEMFILE=#{ENV.fetch('BUNDLE_GEMFILE')}"

  enable_coverage :branch

  add_filter "/gemfiles/"
  add_filter "/spec/"
  add_filter "/vendor/"
end
