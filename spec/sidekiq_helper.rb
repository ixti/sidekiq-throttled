require "securerandom"

require "sidekiq/testing"

require "jid_generator"

configure_redis = proc do |config|
  config.redis = {
    :url        =>  "redis://localhost/15",
    :namespace  =>  "sidekiq-throttled-test"
  }
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
    else                 Sidekiq::Testing.fake!(&example)
    end
  end

  config.before :example do
    Sidekiq.redis do |conn|
      conn.del(conn.keys("*") << "*")
    end
  end
end
