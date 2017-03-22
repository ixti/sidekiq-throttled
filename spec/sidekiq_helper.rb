# frozen_string_literal: true

require "securerandom"

require "sidekiq/testing"

module JidGenerator
  def jid
    SecureRandom.hex 12
  end
end

configure_redis = proc do |config|
  redis_opts = { :url => "redis://localhost/15" }

  if "true" == ENV["WITH_REDIS_NAMESPACE"].to_s
    require "redis-namespace"
    redis_opts[:namespace] = "XXX"
  end

  config.redis = redis_opts
end

Sidekiq.configure_server(&configure_redis)
Sidekiq.configure_client(&configure_redis)

RSpec.configure do |config|
  config.include JidGenerator
  config.extend  JidGenerator

  config.around :example do |example|
    Sidekiq::Worker.clear_all

    case example.metadata[:sidekiq]
    when :fake      then Sidekiq::Testing.fake!(&example)
    when :inline    then Sidekiq::Testing.inline!(&example)
    when :disabled  then Sidekiq::Testing.disable!(&example)
    when :enabled   then Sidekiq::Testing.__set_test_mode(nil, &example)
    else                 Sidekiq::Testing.fake!(&example)
    end
  end

  config.before :example do
    Sidekiq.redis do |conn|
      conn.flushdb
      conn.script("flush")
    end
  end
end
