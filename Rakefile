# frozen_string_literal: true
require "bundler/gem_tasks"

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"
RuboCop::RakeTask.new

default_suite = ENV["CI"] ? :spec : %i(spec rubocop verify_measurements)
named_suites  = {
  "rubocop"   => :rubocop,
  "yardstick" => :verify_measurements,
  "rspec"     => :spec
}

task :default => named_suites.fetch(ENV["SUITE"], default_suite)
