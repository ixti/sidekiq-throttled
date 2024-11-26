# frozen_string_literal: true

require "json"

class ThrottledTestJob
  include Sidekiq::Job
  include Sidekiq::Throttled::Job

  def perform(*); end
end

RSpec.describe Sidekiq::Throttled do
  it "registers server middleware" do
    require "sidekiq/processor"
    allow(Sidekiq).to receive(:server?).and_return true

    if Sidekiq::VERSION >= "7.0"
      expect(Sidekiq.default_configuration.server_middleware.exists?(Sidekiq::Throttled::Middlewares::Server))
        .to be true
    else
      expect(Sidekiq.server_middleware.exists?(Sidekiq::Throttled::Middlewares::Server)).to be true
    end
  end

  it "infuses Sidekiq::BasicFetch with our patches" do
    expect(Sidekiq::BasicFetch).to include(Sidekiq::Throttled::Patches::BasicFetch)
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

    it "passes JID and arguments to registered strategy" do
      strategy = Sidekiq::Throttled::Registry.add("foo",
        threshold:   { limit: 1, period: 1 },
        concurrency: { limit: 1 })

      payload_jid = jid
      args        = ["foo", 1]
      message     = %({"class":"foo","jid":#{payload_jid.inspect},"args":#{args.inspect}})

      expect(strategy).to receive(:throttled?).with payload_jid, *args

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

    it "unwraps ActiveJob-jobs job parameters" do
      strategy = Sidekiq::Throttled::Registry.add("wrapped-foo",
        threshold:   { limit: 1, period: 1 },
        concurrency: { limit: 1 })

      payload_jid = jid
      args        = ["foo", 1]
      message     = JSON.dump({
        "class"   => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
        "wrapped" => "wrapped-foo",
        "args"    => [{ "job_class" => "TestJob", "arguments" => args }],
        "jid"     => payload_jid
      })

      expect(strategy).to receive(:throttled?).with payload_jid, *args

      described_class.throttled? message
    end
  end

  describe ".requeue_throttled" do
    let(:sidekiq_config) do
      if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("7.0.0")
        Sidekiq::DEFAULTS
      else
        Sidekiq::Config.new(queues: %w[default]).default_capsule
      end
    end

    let!(:strategy) do
      Sidekiq::Throttled::Registry.add("ThrottledTestJob", threshold: { limit: 1, period: 1 },
        requeue: { to: :other_queue, with: :enqueue })
    end

    it "invokes requeue_throttled on the strategy" do
      payload_jid = jid
      job = { class: "ThrottledTestJob", jid: payload_jid.inspect }.to_json
      work = Sidekiq::BasicFetch::UnitOfWork.new("queue:default", job, sidekiq_config)

      expect(strategy).to receive(:requeue_throttled).with(work)

      described_class.requeue_throttled work
    end
  end
end
