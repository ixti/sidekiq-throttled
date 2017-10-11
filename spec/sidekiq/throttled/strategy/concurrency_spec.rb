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

    context "when dynamic limit returns nil" do
      let(:strategy) { described_class.new :test, :limit => proc { |*| nil } }

      it { is_expected.to be false }

      it "does not uses redis" do
        Sidekiq.redis do |redis|
          expect(redis).not_to receive(:evalsha)
          strategy.throttled? jid
        end
      end
    end

    it "invalidates expired locks avoiding strategy starvation" do
      5.times { strategy.throttled? jid }

      Timecop.travel(Time.now + 900) do
        expect(strategy.throttled?(jid)).to be false
      end
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

  describe "with a dynamic key suffix" do
    subject(:strategy) do
      described_class.new :test, :limit => 5, :key_suffix => -> (i) { i }
    end
    let(:initial_key_input) { 123 }

    describe "#throttled?" do
      subject { strategy.throttled?(jid, key_input) }
      before { 5.times { strategy.throttled?(jid, initial_key_input) } }

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
      before { 3.times { strategy.throttled?(jid, initial_key_input) } }

      describe "for the same input" do
        let(:key_input) { initial_key_input }
        it { is_expected.to eq 3 }
      end

      describe "for a different input" do
        let(:key_input) { 456 }
        it { is_expected.to eq 0 }
      end
    end

    describe "#finalize!" do
      let(:known_jid) { jid }

      before do
        4.times { strategy.throttled?(jid, initial_key_input) }
        strategy.throttled?(known_jid, initial_key_input)
      end

      describe "for the same input" do
        let(:key_input) { initial_key_input }

        it "reduces active concurrency level" do
          strategy.finalize!(known_jid, key_input)
          expect(strategy.throttled?(jid, initial_key_input)).to be false
        end

        it "allows to run exactly one more job afterwards" do
          strategy.finalize!(known_jid, key_input)
          strategy.throttled?(known_jid, key_input)
        end
      end

      describe "for a different input" do
        let(:key_input) { 456 }

        it "does not reduce active concurrency level" do
          strategy.finalize!(known_jid, key_input)
          expect(strategy.count(initial_key_input)).to eq(5)
        end

        it "does not allow running a job afterwards" do
          strategy.finalize!(known_jid, key_input)
          expect(strategy.throttled?(jid, initial_key_input)).to be true
        end
      end
    end

    describe "#reset!" do
      before { 3.times { strategy.throttled?(jid, initial_key_input) } }

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

  describe "with a dynamic limit" do
    subject(:strategy) do
      described_class.new :test, :limit => -> { 5 }
    end

    describe "#throttled?" do
      subject { strategy.throttled?(jid) }

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

  describe "#dynamic?" do
    subject { described_class.new(:test, **kwargs).dynamic? }

    describe "with a dynamic key suffix" do
      let(:kwargs) { { :limit => 5, :key_suffix => -> { "xxx" } } }
      it { is_expected.to be_truthy }
    end

    describe "with a dynamic limit" do
      let(:kwargs) { { :limit => -> { 5 } } }
      it { is_expected.to be_truthy }
    end

    describe "without a dynamic key suffix and static configration" do
      let(:kwargs) { { :limit => 5 } }
      it { is_expected.to be_falsy }
    end
  end
end
