# frozen_string_literal: true

require "sidekiq"

require_relative "./throttled/version"
require_relative "./throttled/configuration"
require_relative "./throttled/patches/basic_fetch"
require_relative "./throttled/registry"
require_relative "./throttled/job"
require_relative "./throttled/middleware"
require_relative "./throttled/worker"

# @see https://github.com/mperham/sidekiq/
module Sidekiq
  # Concurrency and threshold throttling for Sidekiq.
  #
  # Just add somewhere in your bootstrap:
  #
  #     require "sidekiq/throttled"
  #     Sidekiq::Throttled.setup!
  #
  # Once you've done that you can include {Sidekiq::Throttled::Job} to your
  # job classes and configure throttling:
  #
  #     class MyJob
  #       include Sidekiq::Job
  #       include Sidekiq::Throttled::Job
  #
  #       sidekiq_options :queue => :my_queue
  #
  #       sidekiq_throttle({
  #         # Allow maximum 10 concurrent jobs of this class at a time.
  #         :concurrency => { :limit => 10 },
  #         # Allow maximum 1K jobs being processed within one hour window.
  #         :threshold => { :limit => 1_000, :period => 1.hour }
  #       })
  #
  #       def perform
  #         # ...
  #       end
  #     end
  module Throttled
    class << self
      # @return [Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # Hooks throttler into sidekiq.
      #
      # @return [void]
      def setup!
        Sidekiq::Throttled::Patches::BasicFetch.apply!
      end

      # Tells whenever job is throttled or not.
      #
      # @param [String] message Job's JSON payload
      # @return [Boolean]
      def throttled?(message)
        message = JSON.parse message
        job = message.fetch("wrapped") { message.fetch("class") { return false } }
        jid = message.fetch("jid") { return false }

        Registry.get job do |strategy|
          return strategy.throttled?(jid, *message["args"])
        end

        false
      rescue
        false
      end

      # Return throttled job to be executed later, delegating the details of how to do that
      # to the Strategy for that job.
      #
      # @return [void]
      def requeue_throttled(work)
        message = JSON.parse(work.job)
        job_class = Object.const_get(message.fetch("wrapped") { message.fetch("class") { return false } })

        Registry.get job_class do |strategy|
          strategy.requeue_throttled(work, requeue_with: job_class.sidekiq_throttled_requeue_with)
        end
      end
    end
  end

  configure_server do |config|
    config.server_middleware do |chain|
      chain.add Sidekiq::Throttled::Middleware
    end
  end
end
