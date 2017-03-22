# frozen_string_literal: true

require "set"
require "singleton"

require "sidekiq/throttled/patches/queue"
require "sidekiq/throttled/communicator"
require "sidekiq/throttled/queue_name"

module Sidekiq
  module Throttled
    # Singleton class used to pause queues from being processed.
    # For the sake of efficiency it uses {Communicator} behind the scene
    # to notify all processes about paused/resumed queues.
    #
    # @private
    class QueuesPauser
      include Singleton

      # Redis key of Set with paused queues.
      #
      # @return [String]
      PAUSED_QUEUES = "throttled:X:paused_queues"
      private_constant :PAUSED_QUEUES

      # {Communicator} message used to notify that queue needs to be paused.
      #
      # @return [String]
      PAUSE_MESSAGE = "pause"
      private_constant :PAUSE_MESSAGE

      # {Communicator} message used to notify that queue needs to be resumed.
      #
      # @return [String]
      RESUME_MESSAGE = "resume"
      private_constant :RESUME_MESSAGE

      # Initializes singleton instance.
      def initialize
        @paused_queues = Set.new
        @communicator  = Communicator.instance
      end

      # Configures Sidekiq server to keep actual list of paused queues.
      #
      # @private
      # @return [void]
      def setup!
        Patches::Queue.apply!

        Sidekiq.configure_server do
          @communicator.receive PAUSE_MESSAGE do |queue|
            @paused_queues << QueueName.expand(queue)
          end

          @communicator.receive RESUME_MESSAGE do |queue|
            @paused_queues.delete QueueName.expand(queue)
          end

          @communicator.ready do
            @paused_queues.replace paused_queues.map { |q| QueueName.expand q }
          end
        end
      end

      # Returns queues list with paused queues being stripped out.
      #
      # @private
      # @return [Array<String>]
      def filter(queues)
        queues - @paused_queues.to_a
      end

      # Returns list of paused queues.
      #
      # @return [Array<String>]
      def paused_queues
        Sidekiq.redis { |conn| conn.smembers(PAUSED_QUEUES).to_a }
      end

      # Pauses given `queue`.
      #
      # @param [#to_s] queue
      # @return [void]
      def pause!(queue)
        queue = QueueName.normalize queue.to_s

        Sidekiq.redis do |conn|
          conn.sadd(PAUSED_QUEUES, queue)
          @communicator.transmit(conn, PAUSE_MESSAGE, queue)
        end
      end

      # Checks if given `queue` is paused.
      #
      # @param queue [#to_s]
      # @return [Boolean]
      def paused?(queue)
        queue = QueueName.normalize queue.to_s
        Sidekiq.redis { |conn| conn.sismember(PAUSED_QUEUES, queue) }
      end

      # Resumes given `queue`.
      #
      # @param [#to_s] queue
      # @return [void]
      def resume!(queue)
        queue = QueueName.normalize queue.to_s

        Sidekiq.redis do |conn|
          conn.srem(PAUSED_QUEUES, queue)
          @communicator.transmit(conn, RESUME_MESSAGE, queue)
        end
      end
    end
  end
end
