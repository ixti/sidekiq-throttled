# frozen_string_literal: true

require "logger"
require "securerandom"
require "singleton"
require "stringio"

require "sidekiq/testing"

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

if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("6.5.0")
  Sidekiq.options[:queues] = %i[default]
elsif Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("7.0.0")
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

require "sidekiq/web"
Sidekiq::Web.use Rack::Session::Cookie, secret: SecureRandom.hex(32), same_site: true, max_age: 86_400

RSpec.configure do |config|
  config.include JidGenerator
  config.extend  JidGenerator

  config.around do |example|
    PseudoLogger.instance.reset!

    Sidekiq.redis do |conn|
      conn.flushdb
      conn.script("flush")
    end

    if Sidekiq::VERSION >= "6.4.0"
      Sidekiq::Job.clear_all
    else
      Sidekiq::Worker.clear_all
    end

    case example.metadata[:sidekiq]
    when :inline    then Sidekiq::Testing.inline!(&example)
    when :disabled  then Sidekiq::Testing.disable!(&example)
    when :enabled   then Sidekiq::Testing.__set_test_mode(nil, &example)
    else                 Sidekiq::Testing.fake!(&example)
    end
  end
end
