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
    @configuration = Configuration.new

    class << self
      attr_reader :configuration

      def setup!
        Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add Sidekiq::Throttled::Middleware
          end
        end
      end

      # Tells whenever job is throttled or not.
      #
      # @param [String] message Job's JSON payload
      # @return [Boolean]
      def throttled?(message)
        message = Sidekiq.load_json(message)
        job     = message.fetch("wrapped") { message["class"] }
        jid     = message["jid"]

        return false unless job && jid

        Registry.get(job) do |strategy|
          return strategy.throttled?(jid, *message["args"])
        end

        false
      rescue
        false
      end
    end
  end
end
