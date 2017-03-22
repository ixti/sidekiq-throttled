# frozen_string_literal: true

module Sidekiq
  module Throttled
    module Patches
      module Queue
        def paused?
          QueuesPauser.instance.paused? name
        end

        def self.apply!
          require "sidekiq/api"
          ::Sidekiq::Queue.send(:prepend, self)
        end
      end
    end
  end
end
