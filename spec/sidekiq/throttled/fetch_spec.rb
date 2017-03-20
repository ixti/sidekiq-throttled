# frozen_string_literal: true
require "sidekiq/throttled/fetch"

RSpec.describe Sidekiq::Throttled::Fetch, :sidekiq => :disabled do
  subject(:fetcher) { described_class.new options }

  let(:options)       { { :queues => %w(foo bar) } }
  let(:pauser)        { Sidekiq::Throttled::QueuesPauser.instance }
  let(:paused_queues) { pauser.instance_variable_get :@paused_queues }

  before { paused_queues.clear }

  let! :working_class do
    klass = Class.new do
      include Sidekiq::Worker
      include Sidekiq::Throttled::Worker

      sidekiq_options :queue => :foo

      def self.name
        "WorkingClass"
      end
    end

    stub_const(klass.name, klass)
  end

  describe ".bulk_requeue"

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
          "class" => working_class,
          "args"  => Array.new(3) { [] }
        })
      end

      it "pauses job's queue for TIMEOUT seconds" do
        Sidekiq.redis do |redis|
          expect(Sidekiq::Throttled).to receive(:throttled?).and_return(true)

          queue_regexp = /^queue:(foo|bar)$/
          expect(redis).to receive(:brpop)
            .with(queue_regexp, queue_regexp, an_instance_of(Integer))
            .and_call_original

          expect(fetcher.retrieve_work).to be nil

          expect(redis).to receive(:brpop)
            .with("queue:bar", an_instance_of(Integer))

          expect(fetcher.retrieve_work).to be nil
        end
      end
    end

    shared_examples "expected behavior" do
      before do
        Sidekiq::Client.push_bulk({
          "class" => working_class,
          "args"  => Array.new(10) { [2, 3, 5] }
        })
      end

      subject { fetcher.retrieve_work }

      it { is_expected.not_to be nil }

      context "with strictly ordered queues" do
        before { options[:strict] = true }

        it "builds correct redis brpop command" do
          Sidekiq.redis do |conn|
            expect(conn).to receive(:brpop).with("queue:foo", "queue:bar", 2)
            fetcher.retrieve_work
          end
        end

        it "filters queues with QueuesPauser" do
          options[:queues] << "xxx"
          paused_queues.replace %w(queue:xxx)

          Sidekiq.redis do |conn|
            expect(conn).to receive(:brpop).with("queue:foo", "queue:bar", 2)
            fetcher.retrieve_work
          end
        end
      end

      context "with weight-ordered queues" do
        before { options[:strict] = false }

        it "builds correct redis brpop command" do
          Sidekiq.redis do |conn|
            queue_regexp = /^queue:(foo|bar)$/
            expect(conn).to receive(:brpop).with(queue_regexp, queue_regexp, 2)
            fetcher.retrieve_work
          end
        end

        it "filters queues with QueuesPauser" do
          options[:queues] << "xxx"
          paused_queues.replace %w(queue:xxx)

          Sidekiq.redis do |conn|
            queue_regexp = /^queue:(foo|bar)$/
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
        working_class.sidekiq_throttle(:threshold => {
          :limit  => 5,
          :period => 10
        })
      end

      include_examples "expected behavior"
    end

    context "with dynamic configuration" do
      before do
        working_class.sidekiq_throttle(:threshold => {
          :limit  => -> (a, b, _) { a + b },
          :period => -> (a, b, c) { a + b + c }
        })
      end

      include_examples "expected behavior"
    end
  end
end
