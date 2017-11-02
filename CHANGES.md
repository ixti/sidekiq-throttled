## 0.8.1 (2017-11-02)

* Preload job class constant prior trying to get it's throttling strategy.
  ([@ixti])


## 0.8.0 (2017-10-11)

* Refactor concurrency throttling internals to use sorted sets in order to avoid
  starvation in case when finalize! was not called (OOM / redis issues).
  ([@ixti])


## 0.7.3 (2017-06-26)

* [#34](https://github.com/sensortower/sidekiq-throttled/issues/34)
  Fix reset button for sidekiq `>= 4.2`.
  ([@ixti])


## 0.7.2 (2017-04-02)

* Fix summary bar fixer on sidekiq 4.2+.
  ([@ixti])

* Fix regexp used to fix summay bar queues link when ui was enhanced.
  ([@ixti])


## 0.7.1 (2017-03-30)

* Fix summary bar queues link when queue ui was enhanced.
  ([@ixti])

* [#31](https://github.com/sensortower/sidekiq-throttled/pull/31)
  [#30](https://github.com/sensortower/sidekiq-throttled/issues/30)
  Do not throttle if limit is `nil`.
  ([@ixti])


## 0.7.0 (2017-03-22)

* Expose pause/resume queues hidden feature to UI. This was available via API
  since v0.6.0 and today it's finally got it's UI.
  ([@ixti])


## 0.6.7 (2017-03-21)

* Fix fetcher causing workers starvation upon low concurrency thresholds.
  ([@ixti])


## 0.6.6 (2016-10-16)

* [#24](https://github.com/sensortower/sidekiq-throttled/pull/24)
  Fix dynamic `:key_suffix` issue.
  ([@iporsut])


## 0.6.5 (2016-09-04)

* Fix concurrency throttling when redis-namespace is used.
  ([@ixti])


## 0.6.4 (2016-09-02)

* Rename UnitOfWork throttled requeue to `#requeue_throttled`.
  ([@ixti])


## 0.6.3 (2016-09-02)

* Enrich internal API to allow better extensibility.
  ([@ixti])


## 0.6.2 (2016-09-01)

* Add `Fetch.bulk_requeue` used by Sidekiq upon termination.
  ([@ixti])


## 0.6.1 (2016-08-30)

* Trivial internal API change: extracted queues list builder of `Fetch` into
  dedicated internal method, allowing to enhance it with extra custom filters.
  ([@ixti])


## 0.6.0 (2016-08-27)

* [#21](https://github.com/sensortower/sidekiq-throttled/pull/21)
  Allow pause/unpause queues.
  ([@ixti])


## 0.5.0 (2016-08-18)

* Drop Sidekiq 3.x support.
  ([@ixti])


## 0.4.1 (2016-08-18)

* [#15](https://github.com/sensortower/sidekiq-throttled/pull/15)
  Fix throttled web UI on older versions of sidekiq.
  ([@palanglung])


## 0.4.0 (2016-05-17)

* [#14](https://github.com/sensortower/sidekiq-throttled/pull/14)
  Support dynamic configuration of limits and periods.
  ([@azach], [@ixti])


## 0.3.2 (2016-05-16)

* [#13](https://github.com/sensortower/sidekiq-throttled/issues/13)
  Fix throttled BasicFetch with strictly ordered queues on sidekiq 4.
  ([@palanglung], [@ixti])


## 0.3.1 (2016-05-15)

* Precalculate LUA script digests to reduce bandwidth upon nodes reload
  _(which might (and might not) happen if you run thousands of nodes)_.
  ([@ixti])


## 0.3.0 (2016-05-02)

* [#1](https://github.com/sensortower/sidekiq-throttled/issues/1):
  Add Sidekiq 4.0 support.
  ([@ixti])


## 0.2.0 (2016-02-29)

* [#6](https://github.com/sensortower/sidekiq-throttled/pull/6):
  Add dynamic key suffix functionality.
  ([@fhwang])


## 0.1.0 (2015-11-03)

* Initial release.


[@ixti]: https://github.com/ixti
[@fhwang]: https://github.com/fhwang
[@palanglung]: https://github.com/palanglung
[@azach]: https://github.com/azach
[@iporsut]: https://github.com/iporsut
