# frozen_string_literal: true
require "sidekiq/throttled/fetch"

RSpec.describe Sidekiq::Throttled::Fetch, :sidekiq => :disabled do
  let(:options)       { { :queues => %w(foo bar) } }
  let(:pauser)        { Sidekiq::Throttled::QueuesPauser.instance }
  let(:paused_queues) { pauser.instance_variable_get :@paused_queues }

  before { paused_queues.clear }

  subject(:fetcher) { described_class.new options }

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
  it "sleeps instead of BRPOP when queues list is empty"

  describe "#retrieve_work" do
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
          :limit  => ->(a, b, _) { a + b },
          :period => ->(a, b, c) { a + b + c }
        })
      end

      include_examples "expected behavior"
    end
  end
end
