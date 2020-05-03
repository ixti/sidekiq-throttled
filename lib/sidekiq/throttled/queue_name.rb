# frozen_string_literal: true

module Sidekiq
  module Throttled
    # Queue name utility belt.
    #
    # @private
    module QueueName
      # RegExp used to stip out any redisr-namespace prefixes with `queue:`.
      QUEUE_NAME_PREFIX_RE = /.*queue:/.freeze
      private_constant :QUEUE_NAME_PREFIX_RE

      class << self
        # Strips redis-namespace and `queue:` prefix from given queue name.
        #
        # @example
        #
        #   QueueName.normalize "queue:default"
        #   # => "default"
        #
        #   QueueName.normalize "queue:queue:default"
        #   # => "default"
        #
        #   QueueName.normalize "foo:bar:queue:default"
        #   # => "default"
        #
        # @param [#to_s]
        # @return [String]
        def normalize(queue)
          -queue.to_s.sub(QUEUE_NAME_PREFIX_RE, "")
        end

        # Prepends `queue:` prefix to given `queue` name.
        #
        # @note It does not normalizes queue before expanding it, thus
        #   double-call of this method will potentially do some harm.
        #
        # @param [#to_s] queue Queue name
        # @return [String]
        def expand(queue)
          -"queue:#{queue}"
        end
      end
    end
  end
end
