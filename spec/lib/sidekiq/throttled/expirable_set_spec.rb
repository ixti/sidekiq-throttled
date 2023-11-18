# frozen_string_literal: true

require "sidekiq/throttled/expirable_set"

RSpec.describe Sidekiq::Throttled::ExpirableSet do
  subject(:expirable_set) { described_class.new(2.0) }

  it { is_expected.to be_an Enumerable }

  describe ".new" do
    it "raises ArgumentError if given TTL is not Float" do
      expect { described_class.new(42) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError if given TTL is not positive" do
      expect { described_class.new(0.0) }.to raise_error(ArgumentError)
    end
  end

  describe "#add" do
    it "returns self" do
      expect(expirable_set.add("a")).to be expirable_set
    end

    it "adds uniq elements to the set" do
      expirable_set.add("a").add("b").add("b").add("a")

      expect(expirable_set).to contain_exactly("a", "b")
    end
  end

  describe "#each" do
    subject { expirable_set.each }

    before do
      monotonic_time = 0.0

      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { monotonic_time }

      expirable_set.add("lorem")
      expirable_set.add("ipsum")

      monotonic_time += 1

      expirable_set.add("ipsum")

      monotonic_time += 1

      expirable_set.add("dolor")
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
