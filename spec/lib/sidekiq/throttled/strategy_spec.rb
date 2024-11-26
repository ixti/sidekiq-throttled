# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Strategy do
  subject(:strategy) { described_class.new(:foo, **options) }

  let(:threshold)       { { threshold: { limit: 5, period: 10 } } }
  let(:concurrency)     { { concurrency: { limit: 7 } } }
  let(:ten_seconds_ago) { Time.now - 10 }

  before do
    stub_job_class("ThrottledTestJob")
  end

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

    it "sets requeue using :enqueue by default if the argument is not provided" do
      subject = described_class.new(:foo, concurrency: { limit: 123 })

      expect(subject.requeue_options).to eq(with: :enqueue)
    end

    it "sets requeue using :schedule" do
      subject = described_class.new(:foo, concurrency: { limit: 123 }, requeue: { with: :schedule, to: :another_queue })

      expect(subject.requeue_options).to eq(with: :schedule, to: :another_queue)
    end

    it "sets requeue using :enqueue" do
      subject = described_class.new(:foo, concurrency: { limit: 123 }, requeue: { with: :enqueue, to: :another_queue })

      expect(subject.requeue_options).to eq(with: :enqueue, to: :another_queue)
    end

    it "sets requeue using a Proc for with:" do
      with_proc = ->(_arg) { :enqueue }
      subject = described_class.new(:foo, concurrency: { limit: 123 }, requeue: { with: with_proc, to: :another_queue })

      expect(subject.requeue_options).to eq(with: with_proc, to: :another_queue)
    end

    it "raises if with option is invalid" do
      expect do
        described_class.new(:foo, concurrency: { limit: 123 }, requeue: { with: :invalid_with_value })
      end.to raise_error ArgumentError, "requeue: invalid_with_value is not a valid value for :with"
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
    let(:options) { threshold }

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

    context "when using Sidekiq Pro's SuperFetch", :sidekiq_pro do
      let(:sidekiq_config) do
        config = Sidekiq::Config.new(queues: %w[default other_queue])
        config.super_fetch!
        config
      end
      let(:fetcher) { sidekiq_config.default_capsule.fetcher }

      let(:work) { fetcher.retrieve_work }

      before do
        pre_existing_job = fetcher.retrieve_work
        raise "Found pre-existing job: #{pre_existing_job.inspect}" if pre_existing_job

        # Sidekiq is FIFO queue, with head on right side of the list,
        # meaning jobs below will be stored in 3, 2, 1 order.
        ThrottledTestJob.perform_bulk([[1], [2], [3]])
        work
      end

      describe "with parameter with: :enqueue" do
        let(:options) { threshold }

        it "puts the job back on the queue" do
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue })

          # Ensure that the job was removed from default queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          # And added to the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                  ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Ensure that the job is no longer in the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
        end

        it "puts the job back on a different queue when specified" do
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: :other_queue })

          # Ensure that the job was removed from default queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          # And added to the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to eq([["ThrottledTestJob", [1]]])

          # Ensure that the job is no longer in the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
        end

        it "accepts a Proc for :with argument" do
          subject = described_class.new(:foo, **options, requeue: { with: ->(_arg) { :enqueue } })

          # Ensure that the job was removed from default queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          # And added to the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                  ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Ensure that the job is no longer in the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
        end

        it "accepts a Proc for :to argument" do
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: lambda { |_arg|
            :other_queue
          } })

          # Ensure that the job was removed from default queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          # And added to the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to eq([["ThrottledTestJob", [1]]])

          # Ensure that the job is no longer in the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
        end

        describe "with an invalid :to parameter" do
          it "raises an ArgumentError when :to is an invalid type" do
            invalid_to_value = 12_345 # Integer is an invalid type for `to`
            subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: invalid_to_value })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error(ArgumentError, "Invalid argument for `to`")
          end
        end

        context "when :to Proc raises an exception" do
          it "propagates the exception" do
            faulty_proc = ->(*) { raise "Proc error" }
            subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: faulty_proc })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error("Proc error")
          end
        end
      end

      describe "with parameter with: :schedule" do
        context "when threshold constraints given" do
          before do
            allow(subject.threshold).to receive(:retry_in).and_return(300.0)
          end

          context "when requeueing to the same queue" do
            subject { described_class.new(:foo, **options, requeue: { with: :schedule }) }

            it "reschedules for when the threshold strategy says to, plus some jitter" do
              # Ensure that the job was removed from default queue
              expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
              # And added to the private queue
              expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])

              # Requeue the work, see that it ends up in 'schedule'
              expect do
                subject.requeue_throttled(work)
              end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

              item, score = scheduled_redis_item_and_score
              expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
                "queue" => "queue:default")
              expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)

              # Ensure that the job is no longer in the private queue
              expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
            end
          end

          context "when requeueing to a different queue" do
            subject { described_class.new(:foo, **options, requeue: { with: :schedule, to: :other_queue }) }

            it "reschedules to the specified queue" do
              # Ensure that the job was removed from default queue
              expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
              # And added to the private queue
              expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])

              # Requeue the work, see that it ends up in 'schedule'
              expect do
                subject.requeue_throttled(work)
              end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

              item, score = scheduled_redis_item_and_score
              expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
                "queue" => "queue:other_queue")
              expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)

              # Ensure that the job is no longer in the private queue
              expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
            end
          end

          context "when using a Proc for :with argument" do
            subject { described_class.new(:foo, **options, requeue: { with: ->(_arg) { :schedule } }) }

            it "calls the Proc to get the requeue :with setting" do
              # Ensure that the job was removed from default queue
              expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
              # And added to the private queue
              expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])

              # Requeue the work, see that it ends up in 'schedule'
              expect do
                subject.requeue_throttled(work)
              end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

              item, score = scheduled_redis_item_and_score
              expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
                "queue" => "queue:default")
              expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)

              # Ensure that the job is no longer in the private queue
              expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
            end
          end

          context "when using a Proc for :to argument" do
            subject do
              described_class.new(:foo, **options, requeue: { with: :schedule, to: ->(_arg) { :other_queue } })
            end

            it "calls the Proc to get the requeue :to setting" do
              # Ensure that the job was removed from default queue
              expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
              # And added to the private queue
              expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])

              # Requeue the work, see that it ends up in 'schedule'
              expect do
                subject.requeue_throttled(work)
              end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

              item, score = scheduled_redis_item_and_score
              expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
                "queue" => "queue:other_queue")
              expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)

              # Ensure that the job is no longer in the private queue
              expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
            end
          end
        end

        context "when concurrency constraints given" do
          let(:options) { concurrency }

          it "reschedules for when the concurrency strategy says to, plus some jitter" do
            subject = described_class.new(:foo, **options, requeue: { with: :schedule })
            allow(subject.concurrency).to receive(:retry_in).and_return(300.0)

            # Ensure that the job was removed from default queue
            expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
            # And added to the private queue
            expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])

            # Requeue the work, see that it ends up in 'schedule'
            expect do
              subject.requeue_throttled(work)
            end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

            item, score = scheduled_redis_item_and_score
            expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
              "queue" => "queue:default")
            expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)

            # Ensure that the job is no longer in the private queue
            expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
          end
        end

        context "when threshold and concurrency constraints given" do
          let(:options) { threshold.merge concurrency }

          it "reschedules for the later of what the two say, plus some jitter" do
            subject = described_class.new(:foo, **options, requeue: { with: :schedule })
            allow(subject.concurrency).to receive(:retry_in).and_return(300.0)
            allow(subject.threshold).to receive(:retry_in).and_return(500.0)

            # Ensure that the job was removed from default queue
            expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
            # And added to the private queue
            expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])

            # Requeue the work, see that it ends up in 'schedule'
            expect do
              subject.requeue_throttled(work)
            end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

            item, score = scheduled_redis_item_and_score
            expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
              "queue" => "queue:default")
            expect(score.to_f).to be_within(51.0).of(Time.now.to_f + 550.0)

            # Ensure that the job is no longer in the private queue
            expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
          end
        end

        describe "with an invalid :to parameter" do
          let(:options) { threshold }

          it "raises an ArgumentError when :to is an invalid type" do
            invalid_to_value = 12_345 # Integer is an invalid type for `to`
            subject = described_class.new(:foo, **options, requeue: { with: :schedule, to: invalid_to_value })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error(ArgumentError, "Invalid argument for `to`")
          end
        end

        context "when :to Proc raises an exception" do
          let(:options) { threshold }

          it "propagates the exception" do
            faulty_proc = ->(*) { raise "Proc error" }
            subject = described_class.new(:foo, **options, requeue: { with: :schedule, to: faulty_proc })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error("Proc error")
          end
        end

        context "when :with is a Proc returning an invalid value" do
          it "raises an error when Proc returns an unrecognized value" do
            with_proc = ->(*_) { :invalid_value }
            subject = described_class.new(:foo, **options, requeue: { with: with_proc })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error(RuntimeError, "unrecognized :with option invalid_value")
          end
        end
      end

      context "when :with is a Proc returning an invalid value" do
        let(:options) { threshold }

        it "raises an error when Proc returns an unrecognized value" do
          with_proc = ->(*_) { :invalid_value }
          subject = described_class.new(:foo, **options, requeue: { with: with_proc })

          expect do
            subject.requeue_throttled(work)
          end.to raise_error(RuntimeError, "unrecognized :with option invalid_value")
        end
      end

      context "when :with Proc raises an exception" do
        let(:options) { threshold }

        it "propagates the exception" do
          faulty_proc = ->(*) { raise "Proc error" }
          subject = described_class.new(:foo, **options, requeue: { with: faulty_proc })

          expect do
            subject.requeue_throttled(work)
          end.to raise_error("Proc error")
        end
      end

      context "when :to resolves to nil or empty string" do
        let(:options) { threshold }

        it "defaults to work.queue when :to returns nil" do
          to_proc = ->(*_) {}
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: to_proc })

          # Ensure that the job was removed from default queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          # And added to the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                  ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Ensure that the job is no longer in the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
        end

        it "defaults to work.queue when :to returns an empty string" do
          to_proc = ->(*_) { "" }
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: to_proc })

          # Ensure that the job was removed from default queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          # And added to the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to eq([["ThrottledTestJob", [1]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                  ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Ensure that the job is no longer in the private queue
          expect(enqueued_jobs(fetcher.private_queue("default"))).to be_empty
        end
      end

      describe "#reschedule_throttled" do
        let(:options) { threshold }

        context "when job_class is missing from work.job" do
          before do
            invalid_job_data = JSON.parse(work.job).tap do |msg|
              msg.delete("class")
              msg.delete("wrapped")
            end
            allow(work).to receive(:job).and_return(invalid_job_data.to_json)
          end

          it "returns false and does not reschedule the job" do
            expect(Sidekiq::Client).not_to receive(:enqueue_to_in)
            expect(work).not_to receive(:acknowledge)
            expect(subject.send(:reschedule_throttled, work, requeue_to: "queue:default")).to be_falsey
          end
        end
      end

      describe "#retry_in" do
        context "when both strategies return nil" do
          let(:options) { concurrency.merge(threshold) }

          before do
            allow(subject.concurrency).to receive(:retry_in).and_return(nil)
            allow(subject.threshold).to receive(:retry_in).and_return(nil)
          end

          it "raises an error indicating it cannot compute a valid retry interval" do
            expect do
              subject.send(:retry_in, work)
            end.to raise_error("Cannot compute a valid retry interval")
          end
        end
      end
    end

    context "when using Sidekiq BasicFetch" do
      let(:sidekiq_config) do
        Sidekiq::Config.new(queues: %w[default])
      end
      let(:fetcher) { sidekiq_config.default_capsule.fetcher }

      let(:work) { fetcher.retrieve_work }

      before do
        pre_existing_job = fetcher.retrieve_work
        raise "Found pre-existing job: #{pre_existing_job.inspect}" if pre_existing_job

        # Sidekiq is FIFO queue, with head on right side of the list,
        # meaning jobs below will be stored in 3, 2, 1 order.
        ThrottledTestJob.perform_bulk([[1], [2], [3]])
        work
      end

      describe "with parameter with: :enqueue" do
        let(:options) { threshold }

        it "puts the job back on the queue" do
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue })

          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                  ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty
        end

        it "puts the job back on a different queue when specified" do
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: :other_queue })
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to eq([["ThrottledTestJob", [1]]])
        end

        it "accepts a Proc for :with argument" do
          subject = described_class.new(:foo, **options, requeue: { with: ->(_arg) { :enqueue } })
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                  ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty
        end

        it "accepts a Proc for :to argument" do
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: lambda { |_arg|
            :other_queue
          } })
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to eq([["ThrottledTestJob", [1]]])
        end

        describe "with an invalid :to parameter" do
          it "raises an ArgumentError when :to is an invalid type" do
            invalid_to_value = 12_345 # Integer is an invalid type for `to`
            subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: invalid_to_value })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error(ArgumentError, "Invalid argument for `to`")
          end
        end

        context "when :to Proc raises an exception" do
          it "propagates the exception" do
            faulty_proc = ->(*) { raise "Proc error" }
            subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: faulty_proc })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error("Proc error")
          end
        end
      end

      describe "with parameter with: :schedule" do
        context "when threshold constraints given" do
          before do
            allow(subject.threshold).to receive(:retry_in).and_return(300.0)
          end

          context "when requeueing to the same queue" do
            subject { described_class.new(:foo, **options, requeue: { with: :schedule }) }

            it "reschedules for when the threshold strategy says to, plus some jitter" do
              # Requeue the work, see that it ends up in 'schedule'
              expect do
                subject.requeue_throttled(work)
              end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

              item, score = scheduled_redis_item_and_score
              expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
                "queue" => "queue:default")
              expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
            end
          end

          context "when requeueing to a different queue" do
            subject { described_class.new(:foo, **options, requeue: { with: :schedule, to: :other_queue }) }

            it "reschedules to the specified queue" do
              # Requeue the work, see that it ends up in 'schedule'
              expect do
                subject.requeue_throttled(work)
              end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

              item, score = scheduled_redis_item_and_score
              expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
                "queue" => "queue:other_queue")
              expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
            end
          end

          context "when using a Proc for :with argument" do
            subject { described_class.new(:foo, **options, requeue: { with: ->(_arg) { :schedule } }) }

            it "calls the Proc to get the requeue :with setting" do
              # Requeue the work, see that it ends up in 'schedule'
              expect do
                subject.requeue_throttled(work)
              end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

              item, score = scheduled_redis_item_and_score
              expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
                "queue" => "queue:default")
              expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
            end
          end

          context "when using a Proc for :to argument" do
            subject do
              described_class.new(:foo, **options, requeue: { with: :schedule, to: lambda { |_arg|
                :other_queue
              } })
            end

            it "calls the Proc to get the requeue :to setting" do
              # Requeue the work, see that it ends up in 'schedule'
              expect do
                subject.requeue_throttled(work)
              end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

              item, score = scheduled_redis_item_and_score
              expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
                "queue" => "queue:other_queue")
              expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
            end
          end
        end

        context "when concurrency constraints given" do
          let(:options) { concurrency }

          it "reschedules for when the concurrency strategy says to, plus some jitter" do
            subject = described_class.new(:foo, **options, requeue: { with: :schedule })
            allow(subject.concurrency).to receive(:retry_in).and_return(300.0)

            # Requeue the work, see that it ends up in 'schedule'
            expect do
              subject.requeue_throttled(work)
            end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

            item, score = scheduled_redis_item_and_score
            expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
              "queue" => "queue:default")
            expect(score.to_f).to be_within(31.0).of(Time.now.to_f + 330.0)
          end
        end

        context "when threshold and concurrency constraints given" do
          let(:options) { threshold.merge concurrency }

          it "reschedules for the later of what the two say, plus some jitter" do
            subject = described_class.new(:foo, **options, requeue: { with: :schedule })
            allow(subject.concurrency).to receive(:retry_in).and_return(300.0)
            allow(subject.threshold).to receive(:retry_in).and_return(500.0)

            # Requeue the work, see that it ends up in 'schedule'
            expect do
              subject.requeue_throttled(work)
            end.to change { Sidekiq.redis { |conn| conn.zcard("schedule") } }.by(1)

            item, score = scheduled_redis_item_and_score
            expect(JSON.parse(item)).to include("class" => "ThrottledTestJob", "args" => [1],
              "queue" => "queue:default")
            expect(score.to_f).to be_within(51.0).of(Time.now.to_f + 550.0)
          end
        end

        describe "with an invalid :to parameter" do
          it "raises an ArgumentError when :to is an invalid type" do
            invalid_to_value = 12_345 # Integer is an invalid type for `to`
            subject = described_class.new(:foo, **options, requeue: { with: :schedule, to: invalid_to_value })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error(ArgumentError, "Invalid argument for `to`")
          end
        end

        context "when :to Proc raises an exception" do
          it "propagates the exception" do
            faulty_proc = ->(*) { raise "Proc error" }
            subject = described_class.new(:foo, **options, requeue: { with: :schedule, to: faulty_proc })

            expect do
              subject.requeue_throttled(work)
            end.to raise_error("Proc error")
          end
        end
      end

      context "when :with is a Proc returning an invalid value" do
        it "raises an error when Proc returns an unrecognized value" do
          with_proc = ->(*_) { :invalid_value }
          subject = described_class.new(:foo, **options, requeue: { with: with_proc })

          expect do
            subject.requeue_throttled(work)
          end.to raise_error(RuntimeError, "unrecognized :with option invalid_value")
        end
      end

      context "when :with Proc raises an exception" do
        it "propagates the exception" do
          faulty_proc = ->(*) { raise "Proc error" }
          subject = described_class.new(:foo, **options, requeue: { with: faulty_proc })

          expect do
            subject.requeue_throttled(work)
          end.to raise_error("Proc error")
        end
      end

      context "when :to resolves to nil or empty string" do
        it "defaults to work.queue when :to returns nil" do
          to_proc = ->(*_) {}
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: to_proc })

          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                  ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty
        end

        it "defaults to work.queue when :to returns an empty string" do
          to_proc = ->(*_) { "" }
          subject = described_class.new(:foo, **options, requeue: { with: :enqueue, to: to_proc })

          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [3]], ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty

          # Requeue the work
          subject.requeue_throttled(work)

          # See that it is now on the end of the queue
          expect(enqueued_jobs("default")).to eq([["ThrottledTestJob", [1]], ["ThrottledTestJob", [3]],
                                                  ["ThrottledTestJob", [2]]])
          expect(enqueued_jobs("other_queue")).to be_empty
        end
      end

      describe "#reschedule_throttled" do
        let(:options) { threshold }

        context "when job_class is missing from work.job" do
          before do
            invalid_job_data = JSON.parse(work.job).tap do |msg|
              msg.delete("class")
              msg.delete("wrapped")
            end
            allow(work).to receive(:job).and_return(invalid_job_data.to_json)
          end

          it "returns false and does not reschedule the job" do
            expect(Sidekiq::Client).not_to receive(:enqueue_to_in)
            expect(work).not_to receive(:acknowledge)
            expect(subject.send(:reschedule_throttled, work, requeue_to: "queue:default")).to be_falsey
          end
        end
      end

      describe "#retry_in" do
        context "when both strategies return nil" do
          let(:options) { concurrency.merge(threshold) }

          before do
            allow(subject.concurrency).to receive(:retry_in).and_return(nil)
            allow(subject.threshold).to receive(:retry_in).and_return(nil)
          end

          it "raises an error indicating it cannot compute a valid retry interval" do
            expect do
              subject.send(:retry_in, work)
            end.to raise_error("Cannot compute a valid retry interval")
          end
        end
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
