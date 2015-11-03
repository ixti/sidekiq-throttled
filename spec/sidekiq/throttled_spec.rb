RSpec.describe Sidekiq::Throttled, :sidekiq => :disabled do
  describe ".setup!" do
    before do
      require "celluloid"
      require "sidekiq/processor"
      allow(Sidekiq).to receive(:server?).and_return true
      described_class.setup!
    end

    it "presets Sidekiq fetch strategy to Sidekiq::Throttled::BasicFetch" do
      expect(Sidekiq.options[:fetch]).to be Sidekiq::Throttled::BasicFetch
    end

    it "injects Sidekiq::Throttled::Middleware server middleware" do
      expect(Sidekiq.server_middleware.exists? Sidekiq::Throttled::Middleware)
        .to be true
    end
  end

  describe ".throttled?" do
    it "tolerates invalid JSON message" do
      expect(described_class.throttled? "][").to be false
    end

    it "tolerates invalid (not fully populated) messages" do
      expect(described_class.throttled? %({"class" => "foo"})).to be false
    end

    it "tolerates if limiter not registered" do
      message = %({"class":"foo","jid":#{jid.inspect}})
      expect(described_class.throttled? message).to be false
    end

    it "passes JID to registered strategy" do
      strategy = Sidekiq::Throttled::Registry.add("foo", {
        :threshold   => { :limit => 1, :period => 1 },
        :concurrency => { :limit => 1 }
      })

      payload_jid = jid
      message     = %({"class":"foo","jid":#{payload_jid.inspect}})

      expect(strategy).to receive(:throttled?).with payload_jid

      described_class.throttled? message
    end
  end
end
