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
      # Extends worker class with {ClassMethods}.
      #
      # @note Using `included` hook with extending worker with {ClassMethods}
      #   in order to make API inline with `include Sidekiq::Job`.
      #
      # @private
      def self.included(base)
        base.sidekiq_class_attribute :sidekiq_throttled_requeue_options
        base.sidekiq_class_attribute :sidekiq_throttled_strategy_keys
        base.sidekiq_throttled_strategy_keys = []
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
        def sidekiq_throttle(**options)
          strategy_key = options.delete(:as) || default_throttle_key
          strategy_key = normalize_strategy_key(strategy_key)

          raise ArgumentError, "Duplicate throttling strategy: #{strategy_key}" if throttled_strategy_keys.include?(strategy_key)

          Registry.add(strategy_key, **options)

          self.sidekiq_throttled_strategy_keys = throttled_strategy_keys + [strategy_key]
          update_throttled_strategy_options!
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
        def sidekiq_throttle_as(*names)
          keys = normalize_strategy_keys(names)
          raise ArgumentError, "No throttling strategy provided" if keys.empty?
          ensure_unique_strategy_keys!(keys)

          keys.each do |key|
            raise "Strategy not found: #{key}" unless Registry.get(key)
          end

          self.sidekiq_throttled_strategy_keys = keys
          Registry.add_alias(self, keys.first) if keys.length == 1
          update_throttled_strategy_options!
        end

        private

        def throttled_strategy_keys
          Array(sidekiq_throttled_strategy_keys).map(&:to_s)
        end

        def normalize_strategy_keys(keys)
          Array(keys).flatten.compact.map { |key| normalize_strategy_key(key) }
        end

        def normalize_strategy_key(key)
          key.to_s
        end

        def ensure_unique_strategy_keys!(keys)
          duplicates = keys.group_by { |key| key }.select { |_key, items| items.length > 1 }.keys
          raise ArgumentError, "Duplicate throttling strategy: #{duplicates.first}" if duplicates.any?
        end

        def default_throttle_key
          name || to_s
        end

        def update_throttled_strategy_options!
          keys = throttled_strategy_keys
          return if keys.empty?
        
          opts = get_sidekiq_options.dup
        
          if keys.length > 1
            opts["throttled_strategy_keys"] = keys
            opts.delete("throttled_strategy_key")
          elsif keys.first != default_throttle_key
            opts["throttled_strategy_key"] = keys.first
            opts.delete("throttled_strategy_keys")
          else
            opts.delete("throttled_strategy_keys")
            opts.delete("throttled_strategy_key")
          end
        
          sidekiq_options(opts)
        end
      end
    end
  end
end
