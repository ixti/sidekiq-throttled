# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled, :sidekiq => :disabled do
  describe ".setup!" do
    before do
      # #setup! initializes the fetch strategy
      # and raises when queues is empty
      Sidekiq.options[:queues] = ['default']

      require "sidekiq/processor"
      allow(Sidekiq).to receive(:server?).and_return true
      described_class.setup!
    end

    it "presets Sidekiq fetch strategy to Sidekiq::Throttled::Fetch" do
      expect(Sidekiq.options[:fetch]).to be_a(Sidekiq::Throttled::Fetch)
    end

    it "injects Sidekiq::Throttled::Middleware server middleware" do
      expect(Sidekiq.server_middleware.exists?(Sidekiq::Throttled::Middleware))
        .to be true
    end
  end

  describe ".throttled?" do
    it "tolerates invalid JSON message" do
      expect(described_class.throttled?("][")).to be false
    end

    it "tolerates invalid (not fully populated) messages" do
      expect(described_class.throttled?(%({"class" => "foo"}))).to be false
    end

    it "tolerates if limiter not registered" do
      message = %({"class":"foo","jid":#{jid.inspect}})
      expect(described_class.throttled?(message)).to be false
    end

    it "passes JID to registered strategy" do
      strategy = Sidekiq::Throttled::Registry.add("foo",
        :threshold   => { :limit => 1, :period => 1 },
        :concurrency => { :limit => 1 })

      payload_jid = jid
      message     = %({"class":"foo","jid":#{payload_jid.inspect}})

      expect(strategy).to receive(:throttled?).with payload_jid

      described_class.throttled? message
    end
  end
end
