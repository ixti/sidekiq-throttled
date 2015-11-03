RSpec.describe Sidekiq::Throttled::Strategy do
  subject(:strategy) { described_class.new(:foo, **options) }

  let(:threshold)       { { :threshold => { :limit => 5, :period => 10 } } }
  let(:concurrency)     { { :concurrency => { :limit => 7 } } }
  let(:ten_seconds_ago) { Time.now - 10 }

  describe ".new" do
    it "fails if neither :threshold nor :concurrency given" do
      expect { described_class.new(:foo) }.to raise_error ArgumentError
    end
  end

  describe "#throttled?" do
    subject { strategy.throttled? jid }

    context "when threshold constraints given" do
      let(:options) { threshold }

      context "when limit is not yet reached" do
        before { 3.times { strategy.throttled? jid } }
        it { is_expected.to be false }
      end

      context "when limit exceeded" do
        before { 10.times { strategy.throttled? jid } }
        it { is_expected.to be true }
      end
    end

    context "when concurrency constraints given" do
      let(:options) { concurrency }

      context "when limit is not yet reached" do
        before { 6.times { strategy.throttled? jid } }
        it { is_expected.to be false }
      end

      context "when limit exceeded" do
        before { 7.times { strategy.throttled? jid } }
        it { is_expected.to be true }
      end
    end

    context "when both concurrency and threshold given" do
      let(:options) { threshold.merge concurrency }

      context "and threshold limit reached, while concurrency is not" do
        before { 5.times { strategy.throttled? jid } }
        it { is_expected.to be true }
      end

      it "avoids concurrency limit starvation" do
        Timecop.travel ten_seconds_ago do
          4.times.map { jid }.each do |jid|
            strategy.finalize! jid unless strategy.throttled? jid
          end
        end

        4.times.map { jid }.each do |jid|
          strategy.finalize! jid unless strategy.throttled? jid
        end

        expect(subject).to be false
      end

      context "and concurrency limit reached, while threshold is not" do
        before do
          Timecop.travel ten_seconds_ago do
            4.times { strategy.throttled? jid }
          end

          4.times { strategy.throttled? jid }
        end

        it { is_expected.to be true }
      end

      context "end neither concurrency nor threshold limits are reached" do
        it { is_expected.to be false }
      end
    end
  end

  describe "#reset!" do
    context "when only concurrency constraint given" do
      let(:options) { concurrency }

      specify { expect { strategy.reset! }.not_to raise_error }

      it "calls #reset! on concurrency strategy" do
        expect(strategy.concurrency).to receive(:reset!)
        strategy.reset!
      end
    end

    context "when only threshold constraint given" do
      let(:options) { threshold }

      specify { expect { strategy.reset! }.not_to raise_error }

      it "calls #reset! on threshold strategy" do
        expect(strategy.threshold).to receive(:reset!)
        strategy.reset!
      end
    end

    context "when both concurrency and threshold constraints given" do
      let(:options) { concurrency.merge threshold }

      specify { expect { strategy.reset! }.not_to raise_error }

      it "calls #reset! on concurrency strategy" do
        expect(strategy.concurrency).to receive(:reset!)
        strategy.reset!
      end

      it "calls #reset! on threshold strategy" do
        expect(strategy.threshold).to receive(:reset!)
        strategy.reset!
      end
    end
  end
end
