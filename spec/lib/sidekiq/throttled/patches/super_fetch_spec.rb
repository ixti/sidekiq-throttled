# frozen_string_literal: true

require "sidekiq/throttled/patches/super_fetch"
begin
  require "sidekiq/pro/super_fetch"
  SIDEKIQ_PRO_AVAILABLE = true
rescue LoadError
  # Sidekiq Pro is not available
  SIDEKIQ_PRO_AVAILABLE = false
end

RSpec.describe Sidekiq::Throttled::Patches::SuperFetch do
  if SIDEKIQ_PRO_AVAILABLE
    let(:base_queue) { "default" }
    let(:critical_queue) { "critical" }
    let(:config) do
      config = Sidekiq.instance_variable_get(:@config)
      config.super_fetch!
      config.queues = [base_queue, critical_queue]
      config
    end
    let(:fetch) do
      config.default_capsule.fetcher
    end

    before do
      Sidekiq::Throttled.configure { |config| config.cooldown_period = nil }

      bq = base_queue
      cq = critical_queue
      stub_job_class("TestJob") { sidekiq_options(queue: bq) }
      stub_job_class("AnotherTestJob") { sidekiq_options(queue: cq) }

      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0)

      # Give super_fetch a chance to finish its initialization, but also check that there are no pre-existing jobs
      pre_existing_job = fetch.retrieve_work
      raise "Found pre-existing job: #{pre_existing_job.inspect}" if pre_existing_job

      # Sidekiq is FIFO queue, with head on right side of the list,
      # meaning jobs below will be stored in 3, 2, 1 order.
      TestJob.perform_bulk([[1], [2], [3]])
      AnotherTestJob.perform_async(4)
    end

    describe "#retrieve_work" do
      context "when job is not throttled" do
        it "returns unit of work" do
          expect(Array.new(4) { fetch.retrieve_work }).to all be_an_instance_of(Sidekiq::Pro::SuperFetch::UnitOfWork)
        end
      end

      shared_examples "requeues throttled job" do
        it "returns nothing" do
          fetch.retrieve_work

          expect(fetch.retrieve_work).to be(nil)
        end

        it "pushes job back to the head of the queue" do
          fetch.retrieve_work

          expect { fetch.retrieve_work }
            .to change { enqueued_jobs(base_queue) }.to([["TestJob", 2], ["TestJob", 3]])
            .and(keep_unchanged { enqueued_jobs(critical_queue) })
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
              .to change { enqueued_jobs(base_queue) }.to([["TestJob", 2], ["TestJob", 3]])
              .and(change { Sidekiq::Throttled.cooldown.queues }.to(["queue:#{base_queue}"]))
          end

          it "excludes the queue from polling" do
            fetch.retrieve_work

            expect { fetch.retrieve_work }
              .to change { enqueued_jobs(critical_queue) }.to([])
              .and(keep_unchanged { enqueued_jobs(base_queue) })
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
end
