# frozen_string_literal: true

require "logger"
require "securerandom"
require "singleton"
require "stringio"

require "sidekiq"
require "sidekiq/cli"

$TESTING = false # rubocop:disable Style/GlobalVars

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

module JidGenerator
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

if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("7.0.0")
  Sidekiq[:queues] = %i[default]
else
  Sidekiq.configure_server do |config|
    config.queues = %i[default]
  end
end

Sidekiq.configure_server do |config|
  config.redis  = { url: REDIS_URL }
  config.logger = PseudoLogger.instance
end

Sidekiq.configure_client do |config|
  config.redis  = { url: REDIS_URL }
  config.logger = PseudoLogger.instance
end

RSpec.configure do |config|
  config.include JidGenerator
  config.extend  JidGenerator

  config.before do
    PseudoLogger.instance.reset!

    Sidekiq.redis do |conn|
      conn.flushdb
      conn.script("flush")
    end
  end
end
