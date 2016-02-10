# frozen_string_literal: true
RSpec.describe Sidekiq::Throttled::Strategy::Concurrency do
  subject(:strategy) { described_class.new :test, :limit => 5 }

  describe "#throttled?" do
    subject { strategy.throttled? jid }

    context "when limit exceeded" do
      before { 5.times { strategy.throttled? jid } }
      it { is_expected.to be true }
    end

    context "when limit is not exceded" do
      before { 4.times { strategy.throttled? jid } }
      it { is_expected.to be false }
    end
  end

  describe "#count" do
    subject { strategy.count }
    before { 3.times { strategy.throttled? jid } }
    it { is_expected.to eq 3 }
  end

  describe "#finalize!" do
    let(:known_jid) { jid }

    before do
      4.times { strategy.throttled? jid }
      strategy.throttled? known_jid
    end

    it "reduces active concurrency level" do
      strategy.finalize! known_jid
      expect(strategy.throttled?(known_jid)).to be false
    end

    it "allows to run exactly one more job afterwards" do
      strategy.finalize! known_jid
      strategy.throttled? known_jid

      expect(strategy.throttled?(jid)).to be true
    end
  end

  describe "#reset!" do
    before { 3.times { strategy.throttled? jid } }

    it "resets count back to zero" do
      strategy.reset!
      expect(strategy.count).to eq 0
    end
  end
end
