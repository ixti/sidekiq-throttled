# frozen_string_literal: true
require "sidekiq/throttled/basic_fetch"

RSpec.describe Sidekiq::Throttled::BasicFetch, :sidekiq => :disabled do
  subject(:strategy) { described_class.new :queues => %w(foo) }

  before do
    class WorkingClass
      include Sidekiq::Worker
      include Sidekiq::Throttled::Worker

      sidekiq_options :queue => :foo
      sidekiq_throttle :threshold => { :limit => 5, :period => 10 }
    end

    class DynamicWorkingClass
      include Sidekiq::Worker
      include Sidekiq::Throttled::Worker

      sidekiq_options :queue => :foo
      sidekiq_throttle :threshold => {
        :limit => ->(_) { 5 }, :period => ->(_) { 10 }
      }
    end
  end

  describe "#retrieve_work" do
    subject(:work) { strategy.retrieve_work }

    describe "with static limits" do
      before do
        Sidekiq::Client.push_bulk({
          "class" => WorkingClass,
          "args"  => Array.new(10) { [] }
        })
      end

      it { is_expected.not_to be nil }

      context "when limit is not yet reached" do
        before { 3.times { strategy.retrieve_work } }
        it { is_expected.not_to be nil }
      end

      context "when limit exceeded" do
        before { 5.times { strategy.retrieve_work } }

        it { is_expected.to be nil }

        it "pushes fetched job back to the queue" do
          Sidekiq.redis do |conn|
            expect(conn).to receive(:lpush)
            strategy.retrieve_work
          end
        end
      end
    end

    describe "with dynamic limits" do
      before do
        Sidekiq::Client.push_bulk({
          "class" => DynamicWorkingClass,
          "args"  => Array.new(10) { [] }
        })
      end

      it { is_expected.not_to be nil }

      context "when limit is not yet reached" do
        before { 3.times { strategy.retrieve_work } }
        it { is_expected.not_to be nil }
      end

      context "when limit exceeded" do
        before { 5.times { strategy.retrieve_work } }

        it { is_expected.to be nil }

        it "pushes fetched job back to the queue" do
          Sidekiq.redis do |conn|
            expect(conn).to receive(:lpush)
            strategy.retrieve_work
          end
        end
      end
    end
  end
end
