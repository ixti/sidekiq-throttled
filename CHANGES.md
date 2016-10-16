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
