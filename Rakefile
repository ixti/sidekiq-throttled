# frozen_string_literal: true

require "appraisal"
require "bundler/gem_tasks"

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new

task default: ENV["APPRAISAL_INITIALIZED"] ? %i[spec] : %i[appraisal rubocop]
