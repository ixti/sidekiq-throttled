# frozen_string_literal: true

require "sidekiq/throttled/expirable_set"

RSpec.describe Sidekiq::Throttled::ExpirableSet do
  subject(:expirable_set) { described_class.new }

  it { is_expected.to be_an Enumerable }

  describe "#add" do
    it "raises ArgumentError if given TTL is not Float" do
      expect { expirable_set.add("a", ttl: 42) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError if given TTL is not positive" do
      expect { expirable_set.add("a", ttl: 0.0) }.to raise_error(ArgumentError)
    end

    it "returns self" do
      expect(expirable_set.add("a", ttl: 1.0)).to be expirable_set
    end

    it "adds uniq elements to the set" do
      expirable_set.add("a", ttl: 1.0).add("b", ttl: 1.0).add("b", ttl: 1.0).add("a", ttl: 1.0)

      expect(expirable_set).to contain_exactly("a", "b")
    end

    it "uses longest sunset" do
      monotonic_time = 0.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { monotonic_time }

      expirable_set.add("a", ttl: 1.0).add("b", ttl: 42.0).add("b", ttl: 1.0).add("a", ttl: 2.0)

      monotonic_time += 0.5
      expect(expirable_set).to contain_exactly("a", "b")

      monotonic_time += 1.0
      expect(expirable_set).to contain_exactly("a", "b")

      monotonic_time += 0.5
      expect(expirable_set).to contain_exactly("b")
    end
  end

  describe "#each" do
    subject { expirable_set.each }

    before do
      monotonic_time = 0.0

      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { monotonic_time }

      expirable_set.add("lorem", ttl: 1.0)
      expirable_set.add("ipsum", ttl: 1.0)

      monotonic_time += 0.5

      expirable_set.add("ipsum", ttl: 1.0)

      monotonic_time += 0.5

      expirable_set.add("dolor", ttl: 1.0)
    end

    it { is_expected.to be_an(Enumerator) }
    it { is_expected.to contain_exactly("ipsum", "dolor") }

    context "with block given" do
      it "yields each paused queue and returns self" do
        yielded_elements = []

        expect(expirable_set.each { |element| yielded_elements << element }).to be expirable_set
        expect(yielded_elements).to contain_exactly("ipsum", "dolor")
      end
    end
  end
end
