# frozen_string_literal: true
require "sidekiq/throttled/basic_fetch"

RSpec.describe Sidekiq::Throttled::BasicFetch, :sidekiq => :disabled do
  let(:options)     { { :queues => %w(foo bar) } }
  subject(:fetcher) { described_class.new options }

  before do
    class WorkingClass
      include Sidekiq::Worker
      include Sidekiq::Throttled::Worker

      sidekiq_options :queue => :foo
      sidekiq_throttle :threshold => { :limit => 5, :period => 10 }
    end

    Sidekiq::Client.push_bulk({
      "class" => WorkingClass,
      "args"  => Array.new(10) { [] }
    })
  end

  describe "#retrieve_work" do
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
end
