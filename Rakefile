# frozen_string_literal: true

require "bundler/gem_tasks"

desc "Run tests"
task :test do
  rm_rf "coverage"
  rm_rf "gemfiles"

  Bundler.with_original_env do
    sh "bundle exec appraisal generate"

    # XXX: `bundle exec appraisal install` fails on ruby-3.2
    Dir["gemfiles/*.gemfile"].each do |gemfile|
      sh({ "BUNDLE_GEMFILE" => gemfile }, "bundle lock")
      sh({ "BUNDLE_GEMFILE" => gemfile }, "bundle check") do |ok|
        sh({ "BUNDLE_GEMFILE" => gemfile }, "bundle install") unless ok
      end
    end

    sh "bundle exec appraisal rspec --force-colour"
  end
end

desc "Lint codebase"
task :lint do
  sh "bundle exec rubocop --color"
end

task default: %i[test lint]
