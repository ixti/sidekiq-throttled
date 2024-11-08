# frozen_string_literal: true

class ThrottledTestJob
  include Sidekiq::Job
  include Sidekiq::Throttled::Job

  def perform(*); end
end

RSpec.describe Sidekiq::Throttled::Strategy do
  subject(:strategy) { described_class.new(:foo, **options) }

  let(:threshold)       { { threshold: { limit: 5, period: 10 } } }
  let(:concurrency)     { { concurrency: { limit: 7 } } }
  let(:ten_seconds_ago) { Time.now - 10 }

  describe ".new" do
    it "fails if neither :threshold nor :concurrency given" do
      expect { described_class.new(:foo) }.to raise_error ArgumentError
    end

    it "passes given concurrency suffix generator" do
      key_suffix = ->(_) {}

      expect(Sidekiq::Throttled::Strategy::Concurrency).to receive(:new)
        .with("throttled:foo", include(key_suffix: key_suffix))
        .and_call_original

      described_class.new(:foo, concurrency: {
        limit:      123,
        key_suffix: key_suffix
      })
    end

    it "passes given threshold suffix generator" do
      key_suffix = ->(_) {}

      expect(Sidekiq::Throttled::Strategy::Threshold).to receive(:new)
        .with("throttled:foo", include(key_suffix: key_suffix))
        .and_call_original

      described_class.new(:foo, threshold: {
        limit:      123,
        period:     657,
        key_suffix: key_suffix
      })
    end
  end

  describe "#throttled?" do
    subject { strategy.throttled? jid, *job_args }

    let(:job_args) { [] }

    context "when threshold constraints given" do
      let(:options) { threshold }

      context "when limit is not yet reached" do
        before { 3.times { strategy.throttled? jid } }

        it { is_expected.to be false }
      end

      context "when limit exceeded" do
        before { 10.times { strategy.throttled? jid } }

        it { is_expected.to be true }

        context "with observer" do
          let(:observer) { spy }
          let(:options)  { threshold.merge(observer: observer) }

          it "notifies observer" do
            expect(observer).to receive(:call).with(:threshold, 1, 2, 3)
            strategy.throttled?(jid, 1, 2, 3)
          end
        end
      end
    end

    context "when concurrency constraints given" do
      let(:options) { concurrency }

      context "when limit is not yet reached" do
        before { 6.times { strategy.throttled? jid } }

        it { is_expected.to be false }
      end

      context "when limit exceeded" do
        before { 7.times { strategy.throttled? jid } }

        it { is_expected.to be true }

        context "with observe" do
          let(:observer) { spy }
          let(:options)  { concurrency.merge(observer: observer) }

          it "notifies observer" do
            expect(observer).to receive(:call).with(:concurrency, 1, 2, 3)
            strategy.throttled?(jid, 1, 2, 3)
          end
        end
      end
    end

    context "when array of concurrency constraints given" do
      let(:options) { concurrency }

      let(:concurrency) do
        {
          concurrency: [
            { limit: 3, key_suffix: ->(job_arg, *) { job_arg } },
            { limit: 7, key_suffix: ->(_, *) { 1 } }
          ]
        }
      end

      context "with first concurrency rule" do
        let(:job_args) { [11] }

        context "when limit is not yet reached" do
          before { 2.times { strategy.throttled? jid, *job_args } }

          it { is_expected.to be false }
        end

        context "when limit exceeded with observe" do
          let(:observer) { spy }
          let(:options)  { concurrency.merge(observer: observer) }

          before { 3.times { strategy.throttled? jid, *job_args } }

          it { is_expected.to be true }

          it "notifies observer" do
            expect(observer).to receive(:call).with(:concurrency, *job_args)
            strategy.throttled?(jid, *job_args)
          end
        end
      end

      context "with second concurrency rule" do
        let(:job_args) { [10] }

        context "when limit is not yet reached" do
          before { 6.times { |i| strategy.throttled? jid, i } }

          it { is_expected.to be false }
        end

        context "when limit exceeded with observe" do
          let(:observer) { spy }
          let(:options)  { concurrency.merge(observer: observer) }

          before { 7.times { strategy.throttled? jid, *job_args } }

          it { is_expected.to be true }

          it "notifies observer" do
            expect(observer).to receive(:call).with(:concurrency, *job_args)
            strategy.throttled?(jid, *job_args)
          end
        end
      end
    end

    context "when both concurrency and threshold given" do
      let(:options) { threshold.merge concurrency }

      context "when threshold limit reached, while concurrency is not" do
        before { 5.times { strategy.throttled? jid } }

        it { is_expected.to be true }
      end

      it "avoids concurrency limit starvation" do
        Timecop.travel ten_seconds_ago do
          Array.new(4) { jid }.each do |jid|
            strategy.finalize! jid unless strategy.throttled? jid
          end
        end

        Array.new(4) { jid }.each do |jid|
          strategy.finalize! jid unless strategy.throttled? jid
        end

        expect(strategy).not_to be_throttled(jid)
      end

      context "when concurrency limit reached, while threshold is not" do
        before do
          Timecop.travel ten_seconds_ago do
            4.times { strategy.throttled? jid }
          end

          4.times { strategy.throttled? jid }
        end

        it { is_expected.to be true }
      end

      context "when neither concurrency nor threshold limits are reached" do
        it { is_expected.to be false }
      end
    end
  end

  describe "#requeue_throttled" do
    let(:sidekiq_config) do
      if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("7.0.0")
        Sidekiq::DEFAULTS
      else
        Sidekiq::Config.new(queues: %w[default]).default_capsule
      end
    end

    let!(:work) do
      # Sidekiq is FIFO queue, with head on right side of the list,
      # meaning jobs below will be stored in 3, 2, 1 order.
      ThrottledTestJob.perform_bulk([[1], [2], [3]])

      # Pop the work off the queue
      job = Sidekiq.redis do |conn|
        conn.rpop("queue:default")
      end
      Sidekiq::BasicFetch::UnitOfWork.new("queue:default", job, sidekiq_config)
    end

    describe "with parameter with: :enqueue" do
      let(:options) { threshold }

      def enqueued_jobs(queue)
        Sidekiq.redis do |conn|
          conn.lrange("queue:#{queue}", 0, -1).map do |job|
            JSON.parse(job).then do |payload|
              [payload["class"], payload["args"]]
            end
          end
        end
      end

      it "puts the job back on the queue" do
        expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
        expect(enqueued_jobs("other_queue")).to be_empty

        # Requeue the work
        subject.requeue_throttled(work, with: :enqueue)

        # See that it is now on the end of the queue
        expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                ["ThrottledTestJob", [2]]])
        expect(enqueued_jobs("other_queue")).to be_empty
      end

      it "puts the job back on a different queue when specified" do
        expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
        expect(enqueued_jobs("other_queue")).to be_empty

        # Requeue the work
        subject.requeue_throttled(work, with: :enqueue, to: :other_queue)

        # See that it is now on the end of the queue
        expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
        expect(enqueued_jobs("other_queue")).to eq([["ThrottledTestJob", [1]]])
      end

      it "accepts a Proc for :with argument" do
        expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
        expect(enqueued_jobs("other_queue")).to be_empty

        # Requeue the work
        subject.requeue_throttled(work, with: ->(_arg) { :enqueue })

        # See that it is now on the end of the queue
        expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                ["ThrottledTestJob", [2]]])
        expect(enqueued_jobs("other_queue")).to be_empty
      end

      it "accepts a Proc for :to argument" do
        expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
        expect(enqueued_jobs("other_queue")).to be_empty

        # Requeue the work
        subject.requeue_throttled(work, with: :enqueue, to: ->(_arg) { :other_queue })

        # See that it is now on the end of the queue
        expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
        expect(enqueued_jobs("other_queue")).to eq([["ThrottledTestJob", [1]]])
      end
    end

    describe "with parameter with: :schedule" do
      def scheduled_redis_item_and_score
        Sidekiq.redis do |conn|
          # Depending on whether we have redis-client (for Sidekiq 7) or redis-rb (for older Sidekiq),
          # zscan takes different arguments
          if Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new("7.0.0")
            conn.zscan("schedule", 0).last.first
          else
            conn.zscan("schedule").first
          end
        end
      end

      context "when threshold constraints given" do
        let(:options) { threshold }

        before do
          allow(subject.threshold).to receive(:retry_in).and_return(300.0)
        end

        it "reschedules for when the threshold strategy says to, plus some jitter" do
          # Requeue the work, see that it ends up in 'schedule'
          expect do
            subject.requeue_throttled(work, with: :schedule)
          end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

          item, score = scheduled_redis_item_and_score
          expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1], "queue" => "queue:default")
          expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
        end

        it "reschedules for a different queue if specified" do
          # Requeue the work, see that it ends up in 'schedule'
          expect do
            subject.requeue_throttled(work, with: :schedule, to: :other_queue)
          end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

          item, score = scheduled_redis_item_and_score
          expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
            "queue" => "queue:other_queue")
          expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
        end

        it "accepts a Proc for :with argument" do
          # Requeue the work, see that it ends up in 'schedule'
          expect do
            subject.requeue_throttled(work, with: ->(_arg) { :schedule })
          end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

          item, score = scheduled_redis_item_and_score
          expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1], "queue" => "queue:default")
          expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
        end

        it "accepts a Proc for :to argument" do
          # Requeue the work, see that it ends up in 'schedule'
          expect do
            subject.requeue_throttled(work, with: :schedule, to: ->(_arg) { :other_queue })
          end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

          item, score = scheduled_redis_item_and_score
          expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
            "queue" => "queue:other_queue")
          expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
        end
      end

      context "when concurrency constraints given" do
        let(:options) { concurrency }

        before do
          allow(subject.concurrency).to receive(:retry_in).and_return(300.0)
        end

        it "reschedules for when the concurrency strategy says to, plus some jitter" do
          # Requeue the work, see that it ends up in 'schedule'
          expect do
            subject.requeue_throttled(work, with: :schedule)
          end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

          item, score = scheduled_redis_item_and_score
          expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1], "queue" => "queue:default")
          expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
        end
      end

      context "when threshold and concurrency constraints given" do
        let(:options) { threshold.merge concurrency }

        before do
          allow(subject.concurrency).to receive(:retry_in).and_return(300.0)
          allow(subject.threshold).to receive(:retry_in).and_return(500.0)
        end

        it "reschedules for the later of what the two say, plus some jitter" do
          # Requeue the work, see that it ends up in 'schedule'
          expect do
            subject.requeue_throttled(work, with: :schedule)
          end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

          item, score = scheduled_redis_item_and_score
          expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1], "queue" => "queue:default")
          expect(score.to_f).to be_within(51.0).of(Time.now.to_f + 550.0)
        end
      end
    end

    describe "with an invalid :with parameter" do
      let(:options) { threshold }

      it "raises an error when :with is not a valid value" do
        expect { subject.requeue_throttled(work, with: :invalid_with_value) }
          .to raise_error(RuntimeError, "unrecognized :with option invalid_with_value")
      end
    end
  end

  describe "#reset!" do
    context "when only concurrency constraint given" do
      let(:options) { concurrency }

      specify { expect { strategy.reset! }.not_to raise_error }

      it "calls #reset! on concurrency strategy" do
        expect(strategy.concurrency).to receive(:reset!)
        strategy.reset!
      end
    end

    context "when only threshold constraint given" do
      let(:options) { threshold }

      specify { expect { strategy.reset! }.not_to raise_error }

      it "calls #reset! on threshold strategy" do
        expect(strategy.threshold).to receive(:reset!)
        strategy.reset!
      end
    end

    context "when both concurrency and threshold constraints given" do
      let(:options) { concurrency.merge threshold }

      specify { expect { strategy.reset! }.not_to raise_error }

      it "calls #reset! on concurrency strategy" do
        expect(strategy.concurrency).to receive(:reset!)
        strategy.reset!
      end

      it "calls #reset! on threshold strategy" do
        expect(strategy.threshold).to receive(:reset!)
        strategy.reset!
      end
    end
  end

  describe "#dynamic?" do
    subject { strategy.dynamic? }

    let(:options) { concurrency.merge threshold }

    context "when all upstream strategies are non-dynamic" do
      it { is_expected.to be_falsy }
    end

    context "when threshold upstream strategy is dynamic" do
      before do
        allow(strategy.threshold).to receive(:dynamic?).and_return true
      end

      it { is_expected.to be_truthy }
    end

    context "when concurrency upstream strategy is dynamic" do
      before do
        allow(strategy.concurrency).to receive(:dynamic?).and_return true
      end

      it { is_expected.to be_truthy }
    end
  end
end
