# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]


## [2.1.0] - 2026-01-20

### Fixed

- Fix Web UI compatibility with Sidekiq 8.1+ (view file naming and CSRF changes)
  [#228](https://github.com/ixti/sidekiq-throttled/pull/228).
- Fix string key suffix behavior
  [#215](https://github.com/ixti/sidekiq-throttled/pull/215).
- (doc) Update job configuration items docs for clarity
  [#224](https://github.com/ixti/sidekiq-throttled/pull/224).
- (doc) Clarify that key_suffix is not scoped to each strategy
  [#221](https://github.com/ixti/sidekiq-throttled/pull/221).
- (doc) Update docs for requeue strategy
  [#214](https://github.com/ixti/sidekiq-throttled/pull/214).

### Added

- Backlog size aware throttling
  [#209](https://github.com/ixti/sidekiq-throttled/pull/209).


## [2.0.0] - 2025-06-09

### Fixed

- Fixed NoMethodError in throttled job retry logic caused by race condition when
  pending queue drains between throttle check and delay calculation
  [#208](https://github.com/ixti/sidekiq-throttled/pull/208).

### Added

- Add Sidekiq-8.0 support.

### Removed

- (BREAKING) Drop Sidekiq-7.x support
- (BREAKING) Drop Redis-6.x support
- (BREAKING) Drop Ruby-3.0 support
- (BREAKING) Drop Ruby-3.1 support


## [1.5.2] - 2025-01-12

### Fixed

- Fix maximum retry period calculation, and the queue name when job being pushed
  back on queue [#201](https://github.com/ixti/sidekiq-throttled/pull/201).


## [1.5.1] - 2024-12-09

### Changed

- Fix regresssion in `sidekiq_throttle_as` caused by re-scheduler feature
  [#200](https://github.com/ixti/sidekiq-throttled/pull/200).


## [1.5.0] - 2024-11-17

### Added

- Allow configuring whether throttled jobs are put back on the queue immediately
  or scheduled for the future
  [#150](https://github.com/ixti/sidekiq-throttled/pull/150).

### Changed

- Change default cooldown period to `1.0` (was `2.0`),
  and cooldown threshold to `100` (was `1`)
  [#195](https://github.com/ixti/sidekiq-throttled/pull/195).

### Removed

- Drop Sidekiq < 7 support
- Remove deprecated `Sidekiq::Throttled.setup!`


## [1.4.0] - 2024-04-07

### Fixed

- Correctly unwrap `ActiveJob` arguments:
  [#184](https://github.com/ixti/sidekiq-throttled/pull/184),
  [#185](https://github.com/ixti/sidekiq-throttled/pull/185).


## [1.3.0] - 2024-01-18

### Added

- Add Sidekiq Pro 7.0, 7.1, and 7.2 support
- Add Ruby 3.3 support


## [1.2.0] - 2023-12-18

### Added

- Bring back Ruby-2.7.x support


## [1.1.0] - 2023-11-21

### Changed

- Renamed `Sidekiq::Throttled::Middleware` to `Sidekiq::Throttled::Middlewares::Server`

### Deprecated

- `Sidekiq::Throttled.setup!` is now deprecated. If you need to change order of
  the middleware, please manipulate middlewares chains directly.


## [1.0.1] - 2023-11-20

### Added

- Bring back Sidekiq-6.5 support


## [1.0.0] - 2023-11-20

### Added

- Add Sidekiq-7.2 support
- Revive queues cooldown logic
  [#163](https://github.com/ixti/sidekiq-throttled/pull/163)

### Changed

- (BREAKING) Jobs inherit throttling strategy from their parent class, unless
  explicitly overriden

### Fixed

- Correctly finalize throttled jobs when used with ActiveJob
  [#151](https://github.com/ixti/sidekiq-throttled/pull/151)

### Removed

- (BREAKING) Drop Ruby-2.7.x support
- (BREAKING) Drop Sidekiq-6.x.x support
- (BREAKING) Removed `Sidekiq::Throttled.configuration`


## [1.0.0.alpha.1] - 2023-06-08

### Changed

- Upstream `Sidekiq::BasicFetch` is now infused with throttling directly,
  thus default fetch configuration should work on both Sidekiq and Sidekiq-Pro


### Removed

- Remove `Sidekiq::Throttled::BasicFetch` and `Sidekiq::Throttled::Fetch`


## [1.0.0.alpha] - 2023-05-30

### Added

- Add sidekiq 7.0 and 7.1 support
- Add Ruby 3.2 support


### Changed

- Switch README to Asciidoc format
- Switch CHANGES to keepachangelog.com format
- Sidekiq::Throttled::Fetch was renamed to Sidekiq::Throttled::BasicFetch


### Removed

- Drop support of Sidekiq < 6.5.0
- Remove queue pauser. Queues pausing was extracted into a standalone gem:
  [sidekiq-pauzer](https://gitlab.com/ixti/sidekiq-pauzer).
- Remove Sidekiq IPC based on Redis pub/sub
- Remove queue exclusion from fetcher pon throttled job


[unreleased]: https://github.com/ixti/sidekiq-throttled/compare/v2.1.0...main
[2.1.0]: https://github.com/ixti/sidekiq-throttled/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/ixti/sidekiq-throttled/compare/v1.5.2...v2.0.0
[1.5.2]: https://github.com/ixti/sidekiq-throttled/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/ixti/sidekiq-throttled/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/ixti/sidekiq-throttled/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/ixti/sidekiq-throttled/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/ixti/sidekiq-throttled/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/ixti/sidekiq-throttled/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ixti/sidekiq-throttled/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/ixti/sidekiq-throttled/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/ixti/sidekiq-throttled/compare/v1.0.0.alpha.1...v1.0.0
[1.0.0.alpha.1]: https://github.com/ixti/sidekiq-throttled/compare/v1.0.0.alpha...v1.0.0.alpha.1
[1.0.0.alpha]: https://github.com/ixti/sidekiq-throttled/compare/v0.16.1...v1.0.0.alpha
