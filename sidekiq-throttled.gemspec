# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "sidekiq/throttled/version"

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-throttled"
  spec.version       = Sidekiq::Throttled::VERSION
  spec.authors       = ["Alexey Zapparov"]
  spec.email         = ["alexey@zapparov.com"]

  spec.summary       = "Concurrency and threshold throttling for Sidekiq."
  spec.description   = "Concurrency and threshold throttling for Sidekiq."
  spec.homepage      = "https://github.com/ixti/sidekiq-throttled"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match %r{^(test|spec|features)/}
  end

  spec.metadata["rubygems_mfa_required"] = "true"

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7"

  spec.add_runtime_dependency "concurrent-ruby"
  spec.add_runtime_dependency "redis-prescription", ">= 2.2.0"
  spec.add_runtime_dependency "sidekiq", ">= 6.4"

  spec.add_development_dependency "bundler", ">= 2.0"
end
