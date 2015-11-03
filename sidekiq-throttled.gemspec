# coding: utf-8

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "sidekiq/throttled/version"

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-throttled"
  spec.version       = Sidekiq::Throttled::VERSION
  spec.authors       = ["Alexey V Zapparov"]
  spec.email         = ["ixti@member.fsf.org"]

  spec.summary       = "Concurrency and threshold throttling for Sidekiq."
  spec.description   = "Concurrency and threshold throttling for Sidekiq."
  spec.homepage      = "https://github.com/sensortower/sidekiq-throttled"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
    .reject { |f| f.match(%r{^(test|spec|features)/}) }

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency     "sidekiq", "< 4"

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "timecop"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "sinatra", "~> 1.4", ">= 1.4.6"
end
