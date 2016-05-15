# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Strategy::Script do
  let(:logger)        { double :warn => nil }
  let(:lua_script)    { "redis.call('ping')" }
  let(:redis_script)  { described_class.new(lua_script, :logger => logger) }

  it "loads only when needed" do
    Sidekiq.redis do |conn|
      expect(conn).to receive(:script)
        .with("load", lua_script).and_call_original
      redis_script.eval

      expect(conn).not_to receive(:script)
        .with("load", lua_script)
      redis_script.eval
    end
  end

  describe "#eval" do
    before { redis_script.instance_variable_set(:@digest, "xxx") }

    it "warns if server returns unexpected script digest" do
      expect(logger).to receive(:warn).with(/Unexpected script SHA1 digest/)
      redis_script.eval
    end

    it "updates script digest" do
      redis_script.eval
      expect(redis_script.digest).not_to eq("xxx")
    end
  end
end
