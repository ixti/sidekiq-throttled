# frozen_string_literal: true

require "logger"
require "securerandom"
require "singleton"
require "stringio"

require "sidekiq"
require "sidekiq/cli"

begin
  require "sidekiq-pro"
rescue LoadError
  # Sidekiq Pro is not available
end

$TESTING = true # rubocop:disable Style/GlobalVars

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

module SidekiqThrottledHelper
  def new_sidekiq_config
    cfg = Sidekiq::Config.new
    cfg.redis  = { url: REDIS_URL }
    cfg.logger = PseudoLogger.instance
    cfg.logger.level = Logger::WARN
    cfg.server_middleware do |chain|
      chain.add(Sidekiq::Throttled::Middlewares::Server)
    end
    cfg
  end

  # https://github.com/sidekiq/sidekiq/blob/7df28434f03fa1111e9e2834271c020205369f94/test/helper.rb#L30
  def reset_redis!
    if Sidekiq.default_configuration.instance_variable_defined?(:@redis)
      existing_pool = Sidekiq.default_configuration.instance_variable_get(:@redis)
      existing_pool&.shutdown(&:close)
    end

    RedisClient.new(url: REDIS_URL).call("flushall")

    # After resetting redis, create a new Sidekiq::Config instance to avoid ConnectionPool::PoolShuttingDownError
    Sidekiq.instance_variable_set :@config, new_sidekiq_config
    new_sidekiq_config
  end

  def stub_job_class(name, &block)
    klass = stub_const(name, Class.new)

    klass.include(Sidekiq::Job)
    klass.include(Sidekiq::Throttled::Job)

    klass.instance_exec do
      def perform(*); end
    end

    klass.instance_exec(&block) if block
  end

  def enqueued_jobs(queue)
    Sidekiq.redis do |conn|
      conn.lrange("queue:#{queue}", 0, -1).map do |job|
        JSON.parse(job).then do |payload|
          [payload["class"], *payload["args"]]
        end
      end
    end
  end

  def jid
    SecureRandom.hex 12
  end
end

class PseudoLogger < Logger
  include Singleton

  def initialize
    @io = StringIO.new
    super(@io)
  end

  def reset!
    @io.reopen
  end

  def output
    @io.string
  end
end

Sidekiq.configure_server do |config|
  config.queues = %i[default]
  config.redis  = { url: REDIS_URL }
  config.logger = PseudoLogger.instance
end

Sidekiq.configure_client do |config|
  config.redis  = { url: REDIS_URL }
  config.logger = PseudoLogger.instance
end

RSpec.configure do |config|
  config.include SidekiqThrottledHelper

  config.before do
    PseudoLogger.instance.reset!

    reset_redis!
  end
end
