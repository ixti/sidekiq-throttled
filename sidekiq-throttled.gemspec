# frozen_string_literal: true

require_relative "lib/sidekiq/throttled/version"

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-throttled"
  spec.version       = Sidekiq::Throttled::VERSION
  spec.authors       = ["Alexey Zapparov"]
  spec.email         = ["alexey@zapparov.com"]

  spec.summary       = "Concurrency and rate-limit throttling for Sidekiq"
  spec.homepage      = "https://github.com/ixti/sidekiq-throttled"
  spec.license       = "MIT"

  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata["bug_tracker_uri"]       = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"]         = "#{spec.homepage}/blob/v#{spec.version}/CHANGES.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    docs = %w[LICENSE.txt README.adoc].freeze

    `git ls-files -z`.split("\x0").select do |f|
      f.start_with?("lib/") || docs.include?(f)
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7"

  spec.add_runtime_dependency "concurrent-ruby", ">= 1.2.0"
  spec.add_runtime_dependency "redis-prescription", "~> 2.2"
  spec.add_runtime_dependency "sidekiq", ">= 6.5"
end
