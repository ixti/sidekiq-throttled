# frozen_string_literal: true

# internal
require_relative "./registry"

module Sidekiq
  module Throttled
    # Adds helpers to your worker classes
    #
    # @example Usage
    #
    #     class MyJob
    #       include Sidekiq::Job
    #       include Sidekiq::Throttled::Job
    #
    #       sidkiq_options :queue => :my_queue
    #       sidekiq_throttle :threshold => { :limit => 123, :period => 1.hour },
    #                        :requeue => { :to => :other_queue, :with => :schedule }
    #
    #       def perform
    #         # ...
    #       end
    #     end
    #
    # @see ClassMethods
    module Job
      VALID_VALUES_FOR_REQUEUE_WITH = %i[enqueue schedule].freeze

      # Extends worker class with {ClassMethods}.
      #
      # @note Using `included` hook with extending worker with {ClassMethods}
      #   in order to make API inline with `include Sidekiq::Job`.
      #
      # @private
      def self.included(base)
        worker.sidekiq_class_attribute :sidekiq_throttled_requeue_options
        base.extend(ClassMethods)
      end

      # Helper methods added to the singleton class of destination
      module ClassMethods
        # Registers some strategy for the worker.
        #
        # @example Allow max 123 MyJob jobs per hour
        #
        #     class MyJob
        #       include Sidekiq::Job
        #       include Sidekiq::Throttled::Job
        #
        #       sidekiq_throttle({
        #         :threshold => { :limit => 123, :period => 1.hour }
        #       })
        #     end
        #
        # @example Allow max 10 concurrently running MyJob jobs
        #
        #     class MyJob
        #       include Sidekiq::Job
        #       include Sidekiq::Throttled::Job
        #
        #       sidekiq_throttle({
        #         :concurrency => { :limit => 10 }
        #       })
        #     end
        #
        # @example Allow max 10 concurrent MyJob jobs and max 123 per hour
        #
        #     class MyJob
        #       include Sidekiq::Job
        #       include Sidekiq::Throttled::Job
        #
        #       sidekiq_throttle({
        #         :threshold => { :limit => 123, :period => 1.hour },
        #         :concurrency => { :limit => 10 }
        #       })
        #     end
        #
        # @example Allow max 123 MyJob jobs per hour; when jobs are throttled, schedule them for later in :other_queue
        #
        #     class MyJob
        #       include Sidekiq::Job
        #       include Sidekiq::Throttled::Job
        #
        #       sidekiq_throttle({
        #         :threshold => { :limit => 123, :period => 1.hour },
        #         :requeue => { :to => :other_queue, :with => :schedule }
        #       })
        #     end
        #
        # @param [Hash] requeue What to do with jobs that are throttled
        # @see Registry.add
        # @return [void]
        def sidekiq_throttle(**kwargs)
          requeue_options = Throttled.configuration.default_requeue_options.merge(kwargs.delete(:requeue) || {})
          unless VALID_VALUES_FOR_REQUEUE_WITH.include?(requeue_options[:with])
            raise ArgumentError, "requeue: #{requeue_options[:with]} is not a valid value for :with"
          end

          self.sidekiq_throttled_requeue_options = requeue_options

          Registry.add(self, **kwargs)
        end

        # Adds current worker to preconfigured throttling strategy. Allows
        # sharing same pool for multiple workers.
        #
        # First of all we need to create shared throttling strategy:
        #
        #     # Create google_api throttling strategy
        #     Sidekiq::Throttled::Registry.add(:google_api, {
        #       :threshold => { :limit => 123, :period => 1.hour },
        #       :concurrency => { :limit => 10 }
        #     })
        #
        # Now we can assign it to our workers:
        #
        #     class FetchProfileJob
        #       include Sidekiq::Job
        #       include Sidekiq::Throttled::Job
        #
        #       sidekiq_throttle_as :google_api
        #     end
        #
        #     class FetchCommentsJob
        #       include Sidekiq::Job
        #       include Sidekiq::Throttled::Job
        #
        #       sidekiq_throttle_as :google_api
        #     end
        #
        # With the above configuration we ensure that there are maximum 10
        # concurrently running jobs of FetchProfileJob or FetchCommentsJob
        # allowed. And only 123 jobs of those are executed per hour.
        #
        # In other words, it will allow:
        #
        # - only `X` concurrent `FetchProfileJob`s
        # - max `XX` `FetchProfileJob` per hour
        # - only `Y` concurrent `FetchCommentsJob`s
        # - max `YY` `FetchCommentsJob` per hour
        #
        # Where `(X + Y) == 10` and `(XX + YY) == 123`
        #
        # @see Registry.add_alias
        # @return [void]
        def sidekiq_throttle_as(name)
          Registry.add_alias(self, name)
        end
      end
    end
  end
end
