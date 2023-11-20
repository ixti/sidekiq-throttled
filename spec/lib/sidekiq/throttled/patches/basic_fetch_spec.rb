# frozen_string_literal: true

require "sidekiq/throttled/patches/basic_fetch"

RSpec.describe Sidekiq::Throttled::Patches::BasicFetch do
  def stub_job_class(name, &block)
    klass = stub_const(name, Class.new)

    klass.include(Sidekiq::Job)
    klass.include(Sidekiq::Throttled::Job)

    klass.instance_exec do
      def perform(*); end
    end

    klass.instance_exec(&block) if block
  end

  def enqueued_jobs(queue)
    Sidekiq.redis do |conn|
      conn.lrange("queue:#{queue}", 0, -1).map do |job|
        JSON.parse(job).then do |payload|
          [payload["class"], *payload["args"]]
        end
      end
    end
  end

  let(:fetch) do
    if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("7.0.0")
      Sidekiq.instance_variable_set(:@config, Sidekiq::DEFAULTS.dup)
      Sidekiq.queues = %w[default critical]
      Sidekiq::BasicFetch.new(Sidekiq)
    else
      config = Sidekiq::Config.new
      config.queues = %w[default critical]
      Sidekiq::BasicFetch.new(config.default_capsule)
    end
  end

  before do
    Sidekiq::Throttled.configure { |config| config.cooldown_period = nil }

    stub_job_class("TestJob")
    stub_job_class("AnotherTestJob") { sidekiq_options(queue: :critical) }

    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0)

    # Sidekiq is FIFO queue, with head on right side of the list,
    # meaning jobs below will be stored in 3, 2, 1 order.
    TestJob.perform_async(1)
    TestJob.perform_async(2)
    TestJob.perform_async(3)
    AnotherTestJob.perform_async(4)
  end

  describe "#retrieve_work" do
    context "when job is not throttled" do
      it "returns unit of work" do
        expect(Array.new(4) { fetch.retrieve_work }).to all be_an_instance_of(Sidekiq::BasicFetch::UnitOfWork)
      end
    end

    shared_examples "requeues throttled job" do
      it "returns nothing" do
        fetch.retrieve_work

        expect(fetch.retrieve_work).to be_nil
      end

      it "pushes job back to the head of the queue" do
        fetch.retrieve_work

        expect { fetch.retrieve_work }
          .to change { enqueued_jobs("default") }.to([["TestJob", 2], ["TestJob", 3]])
          .and(keep_unchanged { enqueued_jobs("critical") })
      end

      context "when queue cooldown kicks in" do
        before do
          Sidekiq::Throttled.configure do |config|
            config.cooldown_period    = 2.0
            config.cooldown_threshold = 1
          end

          fetch.retrieve_work
        end

        it "updates cooldown queues" do
          expect { fetch.retrieve_work }
            .to change { enqueued_jobs("default") }.to([["TestJob", 2], ["TestJob", 3]])
            .and(change { Sidekiq::Throttled.cooldown.queues }.to(["queue:default"]))
        end

        it "excludes the queue from polling" do
          fetch.retrieve_work

          expect { fetch.retrieve_work }
            .to change { enqueued_jobs("critical") }.to([])
            .and(keep_unchanged { enqueued_jobs("default") })
        end
      end
    end

    context "when job was throttled due to concurrency" do
      before { TestJob.sidekiq_throttle(concurrency: { limit: 1 }) }

      include_examples "requeues throttled job"
    end

    context "when job was throttled due to threshold" do
      before { TestJob.sidekiq_throttle(threshold: { limit: 1, period: 60 }) }

      include_examples "requeues throttled job"
    end
  end
end
