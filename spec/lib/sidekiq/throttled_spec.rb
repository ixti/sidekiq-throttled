# frozen_string_literal: true

require "json"

RSpec.describe Sidekiq::Throttled do
  describe ".setup!" do
    it "infuses Sidekiq::BasicFetch with our patches" do
      described_class.setup!

      expect(Sidekiq::BasicFetch).to include(Sidekiq::Throttled::Patches::BasicFetch)
    end

    it "registers server middleware" do
      require "sidekiq/processor"

      described_class.setup!

      allow(Sidekiq).to receive(:server?).and_return true

      if Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new("7.0.0")
        expect(Sidekiq.default_configuration.server_middleware.exists?(Sidekiq::Throttled::Middlewares::Server))
          .to be true
      else
        expect(Sidekiq.server_middleware.exists?(Sidekiq::Throttled::Middlewares::Server)).to be true
      end
    end

    if Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new("7.0.0")
      context "with SuperFetch", :sidekiq_pro do
        it "sets up orphan handling" do
          config = Sidekiq.instance_variable_get(:@config)

          config.super_fetch! do
            Kernel.exit # Just to test it's being called
          end

          described_class.setup!

          expect(described_class).to receive(:recover!).with "foo"
          expect(Kernel).to receive(:exit)

          config.default_capsule.fetcher.notify_orphan("foo")
        end
      end
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
        threshold:   { limit: 1, period: 1 },
        concurrency: { limit: 1 })

      payload_jid = jid
      message     = %({"class":"foo","jid":#{payload_jid.inspect}})

      expect(strategy).to receive(:throttled?).with payload_jid

      described_class.throttled? message
    end

    it "unwraps ActiveJob-jobs default sidekiq adapter" do
      strategy = Sidekiq::Throttled::Registry.add("wrapped-foo",
        threshold:   { limit: 1, period: 1 },
        concurrency: { limit: 1 })

      payload_jid = jid
      message     = JSON.dump({
        "class"   => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
        "wrapped" => "wrapped-foo",
        "jid"     => payload_jid
      })

      expect(strategy).to receive(:throttled?).with payload_jid

      described_class.throttled? message
    end

    it "unwraps ActiveJob-jobs custom sidekiq adapter" do
      strategy = Sidekiq::Throttled::Registry.add("JobClassName",
        threshold:   { limit: 1, period: 1 },
        concurrency: { limit: 1 })

      payload_jid = jid
      message     = JSON.dump({
        "class"   => "ActiveJob::QueueAdapters::SidekiqCustomAdapter::JobWrapper",
        "wrapped" => "JobClassName",
        "jid"     => payload_jid
      })

      expect(strategy).to receive(:throttled?).with payload_jid

      described_class.throttled? message
    end
  end

  describe ".recover!" do
    it "tolerates invalid JSON message" do
      expect(described_class.recover!("][")).to be false
    end

    it "tolerates invalid (not fully populated) messages" do
      expect(described_class.recover!(%({"class" => "foo"}))).to be false
    end

    it "tolerates if limiter not registered" do
      message = %({"class":"foo","jid":#{jid.inspect}})
      expect(described_class.recover!(message)).to be false
    end

    it "passes JID to registered strategy" do
      strategy = Sidekiq::Throttled::Registry.add("foo",
        threshold:   { limit: 1, period: 1 },
        concurrency: { limit: 1 })

      payload_jid = jid
      message     = %({"class":"foo","jid":#{payload_jid.inspect}})

      expect(strategy).to receive(:finalize!).with payload_jid

      described_class.recover! message
    end

    it "unwraps ActiveJob-jobs default sidekiq adapter" do
      strategy = Sidekiq::Throttled::Registry.add("wrapped-foo",
        threshold:   { limit: 1, period: 1 },
        concurrency: { limit: 1 })

      payload_jid = jid
      message     = JSON.dump({
        "class"   => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
        "wrapped" => "wrapped-foo",
        "jid"     => payload_jid
      })

      expect(strategy).to receive(:finalize!).with payload_jid

      described_class.recover! message
    end

    it "unwraps ActiveJob-jobs custom sidekiq adapter" do
      strategy = Sidekiq::Throttled::Registry.add("JobClassName",
        threshold:   { limit: 1, period: 1 },
        concurrency: { limit: 1 })

      payload_jid = jid
      message     = JSON.dump({
        "class"   => "ActiveJob::QueueAdapters::SidekiqCustomAdapter::JobWrapper",
        "wrapped" => "JobClassName",
        "jid"     => payload_jid
      })

      expect(strategy).to receive(:finalize!).with payload_jid

      described_class.recover! message
    end
  end
end
