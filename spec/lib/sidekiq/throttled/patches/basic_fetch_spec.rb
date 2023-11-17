# frozen_string_literal: true

require "sidekiq/throttled/patches/basic_fetch"

class ThrottledTestJob
  include Sidekiq::Job
  include Sidekiq::Throttled::Job

  def perform(*); end
end

RSpec.describe Sidekiq::Throttled::Patches::BasicFetch do
  subject(:fetch) do
    config = Sidekiq::Config.new
    config.queues = %w[default]
    Sidekiq::BasicFetch.new(config.default_capsule)
  end

  describe "#retrieve_work" do
    def enqueued_jobs(queue)
      Sidekiq.redis do |conn|
        conn.lrange("queue:#{queue}", 0, -1).map do |job|
          JSON.parse(job).then do |payload|
            [payload["class"], payload["args"]]
          end
        end
      end
    end

    before do
      # Sidekiq is FIFO queue, with head on right side of the list,
      # meaning jobs below will be stored in 3, 2, 1 order.
      ThrottledTestJob.perform_bulk([[1], [2], [3]])
    end

    context "when job is not throttled" do
      it "returns unit of work" do
        expect(fetch.retrieve_work).to be_an_instance_of(Sidekiq::BasicFetch::UnitOfWork)
      end
    end

    context "when job was throttled due to concurrency" do
      before do
        ThrottledTestJob.sidekiq_throttle(concurrency: { limit: 1 })
        fetch.retrieve_work
      end

      it "returns nothing" do
        expect(fetch.retrieve_work).to be_nil
      end

      it "pushes job back to the head of the queue" do
        expect { fetch.retrieve_work }
          .to change { enqueued_jobs("default") }
          .to eq([["ThrottledTestJob", [2]], ["ThrottledTestJob", [3]]])
      end
    end

    context "when job was throttled due to threshold" do
      before do
        ThrottledTestJob.sidekiq_throttle(threshold: { limit: 1, period: 60 })
        fetch.retrieve_work
      end

      it "returns nothing" do
        expect(fetch.retrieve_work).to be_nil
      end

      it "pushes job back to the head of the queue" do
        expect { fetch.retrieve_work }
          .to change { enqueued_jobs("default") }
          .to eq([["ThrottledTestJob", [2]], ["ThrottledTestJob", [3]]])
      end
    end
  end
end
