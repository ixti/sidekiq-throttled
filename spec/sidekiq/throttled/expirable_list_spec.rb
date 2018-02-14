# frozen_string_literal: true

require "sidekiq/throttled/expirable_list"

RSpec.describe Sidekiq::Throttled::ExpirableList, :sidekiq => :disabled do
  subject(:list) { described_class.new ttl }

  let(:ttl) { 3 }

  it { is_expected.to be_an Enumerable }

  describe "#each", :time => :frozen do
    before do
      5.times do |i|
        expect(Concurrent)
          .to receive(:monotonic_time)
          .and_return(i.to_f)

        list << (i + 1)
      end
    end

    context "without block given" do
      subject(:enum) { list.each }

      it { is_expected.to be_an Enumerator }

      it "enumerates over non-expired keys only" do
        expect(Concurrent)
          .to receive(:monotonic_time)
          .and_return(5.0)

        expect { |b| enum.each(&b) }
          .to yield_successive_args(3, 4, 5)
      end
    end

    it "enumerates over non-expired keys only" do
      expect(Concurrent)
        .to receive(:monotonic_time)
        .and_return(5.0)

      expect { |b| list.each(&b) }
        .to yield_successive_args(3, 4, 5)
    end
  end
end
