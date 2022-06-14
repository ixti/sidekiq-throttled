# frozen_string_literal: true

require "securerandom"

require "sidekiq/testing"

module JidGenerator
  def jid
    SecureRandom.hex 12
  end
end

configure_redis = proc do |config|
  config.redis = { :url => "redis://localhost/15" }
end

Sidekiq.configure_server(&configure_redis)
Sidekiq.configure_client(&configure_redis)

# See https://github.com/mperham/sidekiq/blob/v6.2.0/Changes.md
if Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new("6.2.0")
  require "sidekiq/web"
  Sidekiq::Web.use Rack::Session::Cookie, :secret => SecureRandom.hex(32), :same_site => true, :max_age => 86_400
end

RSpec.configure do |config|
  config.include JidGenerator
  config.extend  JidGenerator

  config.around do |example|
    if Sidekiq::VERSION >= "6.3.0"
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

  config.before do
    Sidekiq.redis do |conn|
      conn.flushdb
      conn.script("flush")
    end
  end
end
