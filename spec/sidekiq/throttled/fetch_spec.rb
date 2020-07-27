# frozen_string_literal: true

require "sidekiq/api"
require "sidekiq/throttled/fetch"

require "support/working_class_hero"

RSpec.describe Sidekiq::Throttled::Fetch, :sidekiq => :disabled do
  subject(:fetcher) { described_class.new options }

  let(:options)       { { :queues => queues } }
  let(:queues)        { %w[heroes dreamers] }
  let(:pauser)        { Sidekiq::Throttled::QueuesPauser.instance }
  let(:paused_queues) { pauser.instance_variable_get :@paused_queues }

  before { paused_queues.clear }

  describe ".new" do
    it "fails if :queues are missing" do
      expect { described_class.new({}) }.to raise_error(KeyError, /:queues/)
    end

    it "fails if :queues are empty" do
      expect { described_class.new(:queues => []) }
        .to raise_error(ArgumentError, /:queues/)
    end

    it "is non-strict by default" do
      fetcher = described_class.new(:queues => queues)
      expect(fetcher.instance_variable_get(:@strict)).to be_falsy
    end

    it "cooldowns queues with TIMEOUT by default" do
      expect(Sidekiq::Throttled::ExpirableList)
        .to receive(:new)
        .with(described_class::TIMEOUT)
        .and_call_original

      described_class.new(:queues => queues)
    end

    it "allows override throttled queues cooldown period" do
      expect(Sidekiq::Throttled::ExpirableList)
        .to receive(:new)
        .with(1312)
        .and_call_original

      described_class.new(:queues => queues, :throttled_queue_cooldown => 1312)
    end
  end

  describe "#bulk_requeue" do
    before do
      Sidekiq.redis do |conn|
        conn.rpush("queue:heroes", %w[bob bar])
        conn.rpush("queue:dreamers", "widget")
      end
    end

    let(:q1) { Sidekiq::Queue.new("heroes") }
    let(:q2) { Sidekiq::Queue.new("dreamers") }

    it "requeues" do
      works = 3.times.map { fetcher.retrieve_work }
      expect(q1.size).to eq(0)
      expect(q2.size).to eq(0)

      fetcher.bulk_requeue(works, { queues => [] })
      expect(q1.size).to eq(2)
      expect(q2.size).to eq(1)
    end

    it "is also available on class level for sidekiq < 6.1" do
      works = 3.times.map { fetcher.retrieve_work }
      expect(q1.size).to eq(0)
      expect(q2.size).to eq(0)

      described_class.bulk_requeue(works, { queues => [] })
      expect(q1.size).to eq(2)
      expect(q2.size).to eq(1)
    end
  end

  describe "#retrieve_work" do
    it "sleeps instead of BRPOP when queues list is empty" do
      expect(fetcher).to receive(:filter_queues).and_return([])
      expect(fetcher).to receive(:sleep).with(described_class::TIMEOUT)

      Sidekiq.redis do |redis|
        expect(redis).not_to receive(:brpop)
        expect(fetcher.retrieve_work).to be nil
      end
    end

    context "when received job is throttled", :time => :frozen do
      before do
        Sidekiq::Client.push_bulk({
          "class" => WorkingClassHero,
          "args"  => Array.new(3) { [] }
        })
      end

      it "pauses job's queue for TIMEOUT seconds" do
        Sidekiq.redis do |redis|
          expect(Sidekiq::Throttled).to receive(:throttled?).and_return(true)
          expect(fetcher.retrieve_work).to be nil

          expect(redis).to receive(:brpop)
            .with("queue:dreamers", 2)

          expect(fetcher.retrieve_work).to be nil
        end
      end
    end

    shared_examples "expected behavior" do
      subject { fetcher.retrieve_work }

      before do
        Sidekiq::Client.push_bulk({
          "class" => WorkingClassHero,
          "args"  => Array.new(10) { [2, 3, 5] }
        })
      end

      it { is_expected.not_to be nil }

      context "with strictly ordered queues" do
        before { options[:strict] = true }

        it "builds correct redis brpop command" do
          Sidekiq.redis do |conn|
            expect(conn).to receive(:brpop)
              .with("queue:heroes", "queue:dreamers", 2)
            fetcher.retrieve_work
          end
        end

        it "filters queues with QueuesPauser" do
          options[:queues] << "xxx"
          paused_queues.replace %w[queue:xxx]

          Sidekiq.redis do |conn|
            expect(conn).to receive(:brpop)
              .with("queue:heroes", "queue:dreamers", 2)
            fetcher.retrieve_work
          end
        end
      end

      context "with weight-ordered queues" do
        before { options[:strict] = false }

        it "builds correct redis brpop command" do
          Sidekiq.redis do |conn|
            queue_regexp = /^queue:(heroes|dreamers)$/
            expect(conn).to receive(:brpop).with(queue_regexp, queue_regexp, 2)
            fetcher.retrieve_work
          end
        end

        it "filters queues with QueuesPauser" do
          options[:queues] << "xxx"
          paused_queues.replace %w[queue:xxx]

          Sidekiq.redis do |conn|
            queue_regexp = /^queue:(heroes|dreamers)$/
            expect(conn).to receive(:brpop).with(queue_regexp, queue_regexp, 2)
            fetcher.retrieve_work
          end
        end
      end

      context "when limit is not yet reached" do
        before { 3.times { fetcher.retrieve_work } }

        it { is_expected.not_to be nil }
      end

      context "when limit exceeded" do
        before { 5.times { fetcher.retrieve_work } }

        it { is_expected.to be nil }

        it "pushes fetched job back to the queue" do
          Sidekiq.redis do |conn|
            expect(conn).to receive(:lpush)
            fetcher.retrieve_work
          end
        end
      end
    end

    context "with static configuration" do
      before do
        WorkingClassHero.sidekiq_throttle(:threshold => {
          :limit  => 5,
          :period => 10
        })
      end

      include_examples "expected behavior"
    end

    context "with dynamic configuration" do
      before do
        WorkingClassHero.sidekiq_throttle(:threshold => {
          :limit  => -> (a, b, _) { a + b },
          :period => -> (a, b, c) { a + b + c }
        })
      end

      include_examples "expected behavior"
    end
  end
end
