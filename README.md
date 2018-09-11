# Sidekiq::Throttled

[![Gem Version](https://badge.fury.io/rb/sidekiq-throttled.svg)](http://rubygems.org/gems/sidekiq-throttled)
[![Build Status](https://travis-ci.org/sensortower/sidekiq-throttled.svg?branch=master)](https://travis-ci.org/sensortower/sidekiq-throttled)
[![Code Climate](https://codeclimate.com/github/sensortower/sidekiq-throttled.svg?branch=master)](https://codeclimate.com/github/sensortower/sidekiq-throttled)
[![Coverage Status](https://coveralls.io/repos/github/sensortower/sidekiq-throttled/badge.svg?branch=master)](https://coveralls.io/github/sensortower/sidekiq-throttled?branch=master)
[![API Docs](http://inch-ci.org/github/sensortower/sidekiq-throttled.svg?branch=master)](http://inch-ci.org/github/sensortower/sidekiq-throttled)

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

Once you've done that you can include `Sidekiq::Throttled::Worker` to your
job classes and configure throttling:

``` ruby
class MyWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options :queue => :my_queue

  sidekiq_throttle({
    # Allow maximum 10 concurrent jobs of this class at a time.
    :concurrency => { :limit => 10 },
    # Allow maximum 1K jobs being processed within one hour window.
    :threshold => { :limit => 1_000, :period => 1.hour }
  })

  def perform
    # ...
  end
end
```


### Dynamic throttling

You can throttle jobs dynamically with `:key_suffix` option:

``` ruby
class MyWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options :queue => :my_queue

  sidekiq_throttle({
    # Allow maximum 10 concurrent jobs per user at a time.
    :concurrency => { :limit => 10, :key_suffix => -> (user_id) { user_id } }
  })

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

  sidekiq_throttle({
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
  })

  def perform(user_id)
    # ...
  end
end
```

**NB** Don't forget to specify `:key_suffix` and make it return different values
if you are using dynamic limit/period options. Otherwise you risk getting into
some trouble.


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

* Ruby 2.3.x
* Ruby 2.4.x
* Ruby 2.5.x

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

Copyright (c) 2015-2018 SensorTower Inc.
See LICENSE.md for further details.


[travis]: http://travis-ci.org/sensortower/sidekiq-throttled
[sidekiq]: https://github.com/mperham/sidekiq
