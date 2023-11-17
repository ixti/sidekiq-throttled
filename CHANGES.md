# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Fixed

- Correctly finalize throttled jobs when used with ActiveJob
  [#151](https://github.com/ixti/sidekiq-throttled/pull/151)

### Removed

- (BREAKING) Drop Ruby-2.7.x support


## [1.0.0.alpha.1] - 2023-06-08

### Changes

- Upstream `Sidekiq::BasicFetch` is now infused with throttling directly,
  thus default fetch configuration should work on both Sidekiq and Sidekiq-Pro


### Removed

- Remove `Sidekiq::Throttled::BasicFetch` and `Sidekiq::Throttled::Fetch`


## [1.0.0.alpha] - 2023-05-30

### Added

- Add sidekiq 7.0 and 7.1 support
- Add Ruby 3.2 support


### Changes

- Switch README to Asciidoc format
- Switch CHANGES to keepachangelog.com format
- Sidekiq::Throttled::Fetch was renamed to Sidekiq::Throttled::BasicFetch


### Removed

- Drop support of Sidekiq < 6.5.0
- Remove queue pauser. Queues pausing was extracted into a standalone gem:
  [sidekiq-pauzer](https://gitlab.com/ixti/sidekiq-pauzer).
- Remove Sidekiq IPC based on Redis pub/sub
- Remove queue exclusion from fetcher pon throttled job


[unreleased]: https://github.com/ixti/sidekiq-throttled/compare/v1.0.0.alpha.1...main
[1.0.0.alpha.1]: https://github.com/ixti/sidekiq-throttled/compare/v1.0.0.alpha...v1.0.0.alpha.1
[1.0.0.alpha]: https://github.com/ixti/sidekiq-throttled/compare/v0.16.1...v1.0.0.alpha
