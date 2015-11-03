# Sidekiq::Throttled

[![Build Status](https://travis-ci.org/sensortower/sidekiq-throttled.svg)](https://travis-ci.org/sensortower/sidekiq-throttled)

Concurrency and threshold throttling for Sidekiq.


## Installation

Add this line to your application's Gemfile:

```ruby
gem "sidekiq-throttled"
```

And then execute:

```
$ bundle
```

Or install it yourself as:

```
$ gem install sidekiq-throttled
```


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


## Contributing

* Fork sidekiq-throttled on GitHub
* Make your changes
* Ensure all tests pass (`bundle exec rake`)
* Send a pull request
* If we like them we'll merge them
* If we've accepted a patch, feel free to ask for commit access!


## Copyright

Copyright (c) 2015 SensorTower Inc.
See LICENSE.md for further details.
