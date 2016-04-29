# frozen_string_literal: true
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

  describe "with a dynamic key suffix" do
    subject(:strategy) do
      described_class.new(
        :test, :limit => 5, :period => 10, :key_suffix => -> (i) { i }
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
      described_class.new(
        :test, :limit => -> (_) { 5 }, :period => -> (_) { 10 }
      )
    end

    describe "#throttled?" do
      subject { strategy.throttled? }

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
  end

  describe "#dynamic_keys?" do
    let(:strategy) { described_class.new(:test, **kwargs) }
    subject { strategy.dynamic_keys? }

    describe "with a dynamic key suffix" do
      let(:kwargs) do
        { :limit => 5, :period => 10, :key_suffix => -> (i) { i } }
      end
      it { is_expected.to be_truthy }
    end

    describe "without a dynamic key suffix" do
      let(:kwargs) { { :limit => 5, :period => 10 } }
      it { is_expected.to be_falsy }
    end
  end

  describe "#dynamic_limit?" do
    let(:strategy) { described_class.new(:test, **kwargs) }
    subject { strategy.dynamic_limit? }

    describe "with a dynamic limit" do
      let(:kwargs) do
        { :limit => ->(_) { 5 }, :period => 10 }
      end
      it { is_expected.to be_truthy }
    end

    describe "with a dynamic period" do
      let(:kwargs) do
        { :limit => 5, :period => -> { 10 } }
      end
      it { is_expected.to be_truthy }
    end

    describe "without a dynamic limit or period" do
      let(:kwargs) { { :limit => 5, :period => 10 } }
      it { is_expected.to be_falsy }
    end
  end
end
