# Sidekiq::Throttled

[![Latest Version](https://badge.fury.io/rb/sidekiq-throttled.svg)](http://rubygems.org/gems/sidekiq-throttled)
[![CI Status](https://github.com/sensortower/sidekiq-throttled/workflows/CI/badge.svg?branch=master)](https://github.com/sensortower/sidekiq-throttled/actions?query=workflow%3ACI+branch%3Amaster)
[![Code Quality](https://codeclimate.com/github/sensortower/sidekiq-throttled.svg?branch=master)](https://codeclimate.com/github/sensortower/sidekiq-throttled)
[![Code Coverage](https://coveralls.io/repos/github/sensortower/sidekiq-throttled/badge.svg?branch=master)](https://coveralls.io/github/sensortower/sidekiq-throttled?branch=master)
[![API Docs Quality](http://inch-ci.org/github/sensortower/sidekiq-throttled.svg?branch=master)](http://inch-ci.org/github/sensortower/sidekiq-throttled)
[![API Docs](https://img.shields.io/badge/yard-docs-blue.svg)](http://www.rubydoc.info/gems/sidekiq-throttled)

Concurrency and threshold throttling for [Sidekiq][sidekiq].

## Installation

Add this line to your application's Gemfile:

``` ruby
gem "sidekiq-throttled"
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-throttled


## Usage

Add somewhere in your app's bootstrap (e.g. `config/initializers/sidekiq.rb` if
you are using Rails):

``` ruby
require "sidekiq/throttled"
Sidekiq::Throttled.setup!
```

Load order can be an issue if you are using other Sidekiq plugins and/or middleware.
To prevent any problems, add the `.setup!` call to the bottom of your init file.

Once you've done that you can include `Sidekiq::Throttled::Worker` to your
job classes and configure throttling:

``` ruby
class MyWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options :queue => :my_queue

  sidekiq_throttle(
    # Allow maximum 10 concurrent jobs of this class at a time.
    :concurrency => { :limit => 10 },
    # Allow maximum 1K jobs being processed within one hour window.
    :threshold => { :limit => 1_000, :period => 1.hour }
  )

  def perform
    # ...
  end
end
```

### Observer

You can specify an observer that will be called on throttling. To do so pass an
`:observer` option with callable object:

``` ruby
class MyWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  MY_OBSERVER = lambda do |strategy, *args|
    # do something
  end

  sidekiq_options :queue => :my_queue

  sidekiq_throttle(
    :concurrency => { :limit => 10 },
    :threshold   => { :limit => 100, :period => 1.hour }
    :observer    => MY_OBSERVER
  )

  def perform(*args)
    # ...
  end
end
```

Observer will receive `strategy, *args` arguments, where `strategy` is a Symbol
`:concurrency` or `:threshold`, and `*args` are the arguments that were passed
to the job.


### Dynamic throttling

You can throttle jobs dynamically with `:key_suffix` option:

``` ruby
class MyWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options :queue => :my_queue

  sidekiq_throttle(
    # Allow maximum 10 concurrent jobs per user at a time.
    :concurrency => { :limit => 10, :key_suffix => -> (user_id) { user_id } }
  )

  def perform(user_id)
    # ...
  end
end
```

You can also supply dynamic values for limits and periods by supplying a proc
for these values. The proc will be evaluated at the time the job is fetched
and will receive the same arguments that are passed to the job.

``` ruby
class MyWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options :queue => :my_queue

  sidekiq_throttle(
    # Allow maximum 1000 concurrent jobs of this class at a time for VIPs and 10 for all other users.
    :concurrency => {
      :limit      => ->(user_id) { User.vip?(user_id) ? 1_000 : 10 },
      :key_suffix => ->(user_id) { User.vip?(user_id) ? "vip" : "std" }
    },
    # Allow 1000 jobs/hour to be processed for VIPs and 10/day for all others
    :threshold   => {
      :limit      => ->(user_id) { User.vip?(user_id) ? 1_000 : 10 },
      :period     => ->(user_id) { User.vip?(user_id) ? 1.hour : 1.day },
      :key_suffix => ->(user_id) { User.vip?(user_id) ? "vip" : "std" }
  )

  def perform(user_id)
    # ...
  end
end
```

You also can use several different keys to throttle one worker.

``` ruby
class MyWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options :queue => :my_queue

  sidekiq_throttle(
    # Allow maximum 10 concurrent jobs per project at a time and maximum 2 jobs per user
    :concurrency => [
      { :limit => 10, :key_suffix => -> (project_id, user_id) { project_id } },
      { :limit => 2, :key_suffix => -> (project_id, user_id) { user_id } }
    ]
    # For :threshold it works the same
  )

  def perform(project_id, user_id)
    # ...
  end
end
```

**NB** Don't forget to specify `:key_suffix` and make it return different values
if you are using dynamic limit/period options. Otherwise you risk getting into
some trouble.


### Concurrency throttling fine-tuning

Concurrency throttling is based on distributed locks. Those locks have default
time to live (TTL) set to 15 minutes. If your job takes more than 15 minutes
to finish, lock will be released and you might end up with more jobs running
concurrently than you expect.

This is done to avoid deadlocks - when by any reason (e.g. Sidekiq process was
OOM-killed) cleanup middleware wasn't executed and locks were not released.

If your job takes more than 15 minutes to complete, you can tune concurrency
lock TTL to fit your needs:

``` ruby
# Set concurrency strategy lock TTL to 1 hour.
sidekiq_throttle(:concurrency => { :limit => 20, :ttl => 1.hour.to_i })
```


## Enhanced Queues list

This gem provides ability to pause/resume queues from processing by workers.
So you may simply pause particular queue without need to stop and reconfigure
workers by simply pushing a button on sidekiq web UI.

By default we add *Enhanced Queues* tab with this functionality. But if you
want you can override default *Queues* tab completely (notice that page will
still be available using it's URL, but tab will be pointing enhanced version).
To do so, just call `Sidekiq::Throttled::Web.enhance_queues_tab!` somewhere
in your initializer/bootstrap code. If you are using rails, you might want to
add it right into your `config/routes.rb` file:

``` ruby
# file config/routes.rb

require "sidekiq/web"
require "sidekiq/throttled/web"

Rails.application.routes.draw do
  # ...

  # Replace Sidekiq Queues with enhanced version!
  Sidekiq::Throttled::Web.enhance_queues_tab!

  # Mount Sidekiq Web UI to `/sidekiq` endpoint
  mount Sidekiq::Web => "/sidekiq"

  # ...
end
```


## Supported Ruby Versions

This library aims to support and is [tested against][travis] the following Ruby
versions:

* Ruby 2.4.x
* Ruby 2.5.x
* Ruby 2.6.x

If something doesn't work on one of these versions, it's a bug.

This library may inadvertently work (or seem to work) on other Ruby versions,
however support will only be provided for the versions listed above.

If you would like this library to support another Ruby version or
implementation, you may volunteer to be a maintainer. Being a maintainer
entails making sure all tests run and pass on that implementation. When
something breaks on your implementation, you will be responsible for providing
patches in a timely fashion. If critical issues for a particular implementation
exist at the time of a major release, support for that Ruby version may be
dropped.


## Supported Sidekiq Versions

This library aims to support work with following [Sidekiq][sidekiq] versions:

* Sidekiq 5.0.x
* Sidekiq 5.1.x
* Sidekiq 5.2.x
* Sidekiq 6.0.x
* Sidekiq 6.1.x


## Contributing

* Fork sidekiq-throttled on GitHub
* Make your changes
* Ensure all tests pass (`bundle exec rake`)
* Send a pull request
* If we like them we'll merge them
* If we've accepted a patch, feel free to ask for commit access!


## Development

```
bundle update
bundle exec appraisal install   # install dependencies for all gemfiles
bundle exec appraisal update    # update dependencies for all gemfiles
bundle exec appraisal rspec     # run rspec against each gemfile
bundle exec rubocop             # run static code analysis
```

Don't forget to run `appraisal update` after any changes to `Gemfile`.


## Copyright

Copyright (c) 2015-2020 SensorTower Inc.
See LICENSE.md for further details.


[travis]: http://travis-ci.org/sensortower/sidekiq-throttled
[sidekiq]: https://github.com/mperham/sidekiq
