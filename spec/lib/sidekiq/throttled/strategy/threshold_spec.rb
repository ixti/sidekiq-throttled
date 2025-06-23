# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Strategy::Threshold do
  subject(:strategy) { described_class.new :test, limit: 5, period: 10 }

  describe "#throttled?" do
    subject { strategy.throttled? }

    context "when limit exceeded" do
      before { 5.times { strategy.throttled? } }

      it { is_expected.to be true }

      context "when chill period is over" do
        it { Timecop.travel(Time.now + 11) { is_expected.to be false } }
      end
    end

    context "when limit is not exceded" do
      before { 4.times { strategy.throttled? } }

      it { is_expected.to be false }
    end

    context "when dynamic limit returns nil" do
      let(:strategy) do
        described_class.new :test,
          limit:  proc { |*| },
          period: 10
      end

      it { is_expected.to be false }

      it "does not uses redis" do
        Sidekiq.redis do |redis|
          expect(redis).not_to receive(:evalsha)
          strategy.throttled? jid
        end
      end
    end
  end

  describe "#retry_in" do
    context "when limit exceeded with all jobs happening just now" do
      before { 5.times { strategy.throttled? } }

      it "tells us to wait roughly one period" do
        expect(subject.retry_in).to be_within(0.1).of(10)
      end
    end

    context "when limit exceeded, with first job happening 8 seconds ago" do
      before do
        Timecop.travel(Time.now - 8) do
          strategy.throttled?
        end
        4.times { strategy.throttled? }
      end

      it "tells us to wait 2 seconds" do
        expect(subject.retry_in).to be_within(0.1).of(2)
      end
    end

    context "when limit not exceeded, because the oldest job was more than a period ago" do
      before do
        Timecop.travel(Time.now - 12) do
          strategy.throttled?
        end
        4.times { strategy.throttled? }
      end

      it "tells us we do not need to wait" do
        expect(subject.retry_in).to eq 0
      end
    end

    context "when limit not exceeded, because there are fewer jobs than the limit" do
      before do
        4.times { strategy.throttled? }
      end

      it "tells us we do not need to wait" do
        expect(subject.retry_in).to eq 0
      end
    end

    context "when there is no limit" do
      subject(:strategy) { described_class.new :test, limit: -> {}, period: 10 }

      before { 5.times { strategy.throttled? } }

      it "tells us we do not need to wait" do
        expect(subject.retry_in).to eq 0
      end
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

  describe "with a dynamic key suffix" do
    subject(:strategy) do
      described_class.new(
        :test, limit: 5, period: 10, key_suffix: ->(i) { i }
      )
    end

    let(:initial_key_input) { 123 }

    describe "#throttled?" do
      subject { strategy.throttled?(key_input) }

      before { 5.times { strategy.throttled?(initial_key_input) } }

      describe "when limit exceeded for the same input" do
        let(:key_input) { initial_key_input }

        it { is_expected.to be true }
      end

      describe "when limit exceeded for a different input" do
        let(:key_input) { 456 }

        it { is_expected.to be false }
      end

      describe "when limit is 0" do
        let(:key_input) { initial_key_input }
        let(:strategy) { described_class.new :test, limit: 0, period: 10 }

        it { is_expected.to be true }
      end

      describe "when limit is negative" do
        let(:key_input) { initial_key_input }
        let(:strategy) do
          described_class.new :test, limit: -5, period: 10
        end

        it { is_expected.to be true }
      end
    end

    describe "#count" do
      subject { strategy.count(key_input) }

      before { 3.times { strategy.throttled?(initial_key_input) } }

      describe "for the same input" do
        let(:key_input) { initial_key_input }

        it { is_expected.to eq 3 }
      end

      describe "for a different input" do
        let(:key_input) { 456 }

        it { is_expected.to eq 0 }
      end
    end

    describe "#reset!" do
      before { 3.times { strategy.throttled?(initial_key_input) } }

      describe "for the same input" do
        let(:key_input) { initial_key_input }

        it "resets count back to zero" do
          strategy.reset!(key_input)
          expect(strategy.count(key_input)).to eq 0
        end
      end

      describe "for a different input" do
        let(:key_input) { 456 }

        it "does not reset count back to zero for the initial input" do
          strategy.reset!(key_input)
          expect(strategy.count(initial_key_input)).to eq 3
        end
      end
    end
  end

  describe "with a dynamic limit and period" do
    subject(:strategy) do
      described_class.new(:test, limit: -> { 5 }, period: -> { 10 })
    end

    describe "#throttled?" do
      subject { strategy.throttled? }

      context "when limit exceeded" do
        before { 5.times { strategy.throttled? } }

        it { is_expected.to be true }

        context "when chill period is over" do
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

  describe "#dynamic?" do
    subject { described_class.new(:test, **kwargs).dynamic? }

    describe "with a dynamic key suffix" do
      let(:kwargs) do
        {
          limit:      5,
          period:     10,
          key_suffix: -> { "xxx" }
        }
      end

      it { is_expected.to be_truthy }
    end

    describe "with a dynamic limit" do
      let(:kwargs) do
        {
          limit:  -> { 5 },
          period: 10
        }
      end

      it { is_expected.to be_truthy }
    end

    describe "with a dynamic period" do
      let(:kwargs) do
        {
          limit:  5,
          period: -> { 10 }
        }
      end

      it { is_expected.to be_truthy }
    end

    describe "without a dynamic key suffix and static configration" do
      let(:kwargs) do
        {
          limit:  5,
          period: 10
        }
      end

      it { is_expected.to be_falsy }
    end
  end

  describe "with string key suffix" do
    subject(:strategy) do
      described_class.new(:test, limit: 2, period: 10, key_suffix: "xxx")
    end

    describe "#throttled?" do
      subject { strategy.throttled? }

      before do
        3.times { strategy.throttled? }
      end

      it { is_expected.to be true }
    end
  end
end
