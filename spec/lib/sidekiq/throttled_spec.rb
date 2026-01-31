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

  describe ".throttled_with" do
    it "returns throttled strategies and finalizes the rest" do
      throttled_strategy = instance_double(Sidekiq::Throttled::Strategy)
      open_strategy = instance_double(Sidekiq::Throttled::Strategy)

      payload_jid = jid
      args = ["alpha", 1]
      message = JSON.dump({
        "class" => "ThrottledTestJob",
        "jid" => payload_jid,
        "args" => args,
        "throttled_strategy_keys" => %w[first second]
      })

      allow(Sidekiq::Throttled::Registry).to receive(:get).with("first").and_return(throttled_strategy)
      allow(Sidekiq::Throttled::Registry).to receive(:get).with("second").and_return(open_strategy)

      allow(throttled_strategy).to receive(:throttled?).with(payload_jid, *args).and_return(true)
      allow(open_strategy).to receive(:throttled?).with(payload_jid, *args).and_return(false)

      expect(open_strategy).to receive(:finalize!).with(payload_jid, *args)
      expect(throttled_strategy).not_to receive(:finalize!)

      expect(described_class.throttled_with(message)).to eq([true, [throttled_strategy]])
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

    it "selects the strategy with the maximum cooldown when requeueing" do
      fast_strategy = instance_double(Sidekiq::Throttled::Strategy)
      slow_strategy = instance_double(Sidekiq::Throttled::Strategy)

      payload_jid = jid
      args = ["alpha", 1]
      job = { class: "ThrottledTestJob", jid: payload_jid, args: args }.to_json
      work = Sidekiq::BasicFetch::UnitOfWork.new("queue:default", job, sidekiq_config)

      allow(fast_strategy).to receive(:resolved_requeue_with).with(*args).and_return(:schedule)
      allow(slow_strategy).to receive(:resolved_requeue_with).with(*args).and_return(:schedule)
      allow(fast_strategy).to receive(:retry_in).with(payload_jid, *args).and_return(2.0)
      allow(slow_strategy).to receive(:retry_in).with(payload_jid, *args).and_return(10.0)
      allow(fast_strategy).to receive(:requeue_throttled)
      allow(slow_strategy).to receive(:requeue_throttled)

      described_class.requeue_throttled(work, [fast_strategy, slow_strategy])

      expect(slow_strategy).to have_received(:requeue_throttled).with(work)
      expect(fast_strategy).not_to have_received(:requeue_throttled)
    end
  end
end
