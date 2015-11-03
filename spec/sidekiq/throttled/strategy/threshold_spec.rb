RSpec.describe Sidekiq::Throttled::Strategy::Threshold do
  subject(:strategy) { described_class.new :test, :limit => 5, :period => 10 }

  describe "#throttled?" do
    subject { strategy.throttled? }

    context "when limit exceeded" do
      before { 5.times { strategy.throttled? } }
      it { is_expected.to be true }

      context "and chill period is over" do
        it { Timecop.travel(Time.now + 11) { is_expected.to be false } }
      end
    end

    context "when limit is not exceded" do
      before { 4.times { strategy.throttled? } }
      it { is_expected.to be false }
    end
  end

  describe "#count" do
    subject { strategy.count }
    before { 3.times { strategy.throttled? } }
    it { is_expected.to eq 3 }
  end

  describe "#reset!" do
    before { 3.times { strategy.throttled? } }

    it "resets count back to zero" do
      strategy.reset!
      expect(strategy.count).to eq 0
    end
  end
end
