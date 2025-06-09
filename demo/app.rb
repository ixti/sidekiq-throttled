# frozen_string_literal: true

require "bundler/setup"

require "sidekiq"
require "sidekiq/throttled"

module ThrottledDemo
  class FirstJob
    include Sidekiq::Job
    include Sidekiq::Throttled::Job

    sidekiq_throttle concurrency: { limit: 1 }

    def perform(num)
      puts "performing #{num}..."
    end
  end

  class SecondJob
    include Sidekiq::Job
    include Sidekiq::Throttled::Job

    sidekiq_throttle threshold: { limit: 6, period: 60 }

    def perform(num)
      puts "performing #{num}..."
    end
  end
end
