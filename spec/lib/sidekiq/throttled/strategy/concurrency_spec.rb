# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Strategy::Concurrency do
  subject(:strategy) { described_class.new :test, limit: 5 }

  describe "#initialize" do
    it "accepts all parameters" do
      expect(
        described_class.new(:test, limit: 5, avg_job_duration: 300, lost_job_threshold: 900, key_suffix: -> { "xxx" })
      ).to be_a described_class
    end

    it "accepts ttl as alias of lost_job_threshold" do
      expect(
        described_class.new(:test, limit: 5, avg_job_duration: 300, ttl: 900)
      ).to be_a described_class
    end

    it "doesn't allow lost_job_threshold > avg_job_duration" do
      expect do
        described_class.new(:test, limit: 5, avg_job_duration: 300, lost_job_threshold: 100)
      end
        .to raise_error ArgumentError
    end
  end

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
      let(:strategy) { described_class.new :test, limit: proc { |*| } }

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

    context "when ttl is explicitly set to non-default value" do
      subject(:strategy) { described_class.new :test, limit: 5, ttl: 1000 }

      it "invalidates expired locks avoiding strategy starvation" do
        5.times { strategy.throttled? jid }

        Timecop.travel(Time.now + 900) do
          expect(strategy.throttled?(jid)).to be true
        end

        Timecop.travel(Time.now + 1000) do
          expect(strategy.throttled?(jid)).to be false
        end
      end
    end

    context "when lost_job_threshold is explicitly set to non-default value" do
      subject(:strategy) { described_class.new :test, limit: 5, lost_job_threshold: 1000 }

      it "invalidates expired locks avoiding strategy starvation" do
        5.times { strategy.throttled? jid }

        Timecop.travel(Time.now + 900) do
          expect(strategy.throttled?(jid)).to be true
        end

        Timecop.travel(Time.now + 1000) do
          expect(strategy.throttled?(jid)).to be false
        end
      end
    end
  end

  describe "#retry_in" do
    context "when limit is exceeded with all jobs starting just now" do
      before { 5.times { strategy.throttled? jid } }

      it "tells us to wait roughly the expected time between job completions (expected job duration / max concurrency)" do # rubocop:disable Layout/LineLength
        strategy.throttled? jid # register that we are delaying this job

        expect(subject.retry_in(jid)).to be_within(1).of(300 / 5)
      end
    end

    context "when there is a deep backlog of this type of job" do
      before { 15.times { |a_jid| strategy.throttled? a_jid } }

      it "tells us to wait a time proportional to the approximate backlog size" do
        expect(subject.retry_in(jid)).to be_within(1).of(10 * 300 / 5)
      end
    end

    context "when some jobs have finished" do
      before do
        (1..15).each { |a_jid| strategy.throttled? a_jid } # 5 in-progress; 10 delayed jobs
        (1..5).each { |a_jid| strategy.finalize! a_jid } # finish in-progress jobs
        (6..10).each { |a_jid| strategy.throttled? a_jid } # start next batch of job
      end

      it "tells us to wait a time proportional to the remaining backlog" do
        expect(subject.retry_in(jid)).to be_within(1).of(5 * 300 / 5)
      end
    end

    context "when created with non-default job duration not the default" do
      subject(:strategy) { described_class.new :fast_job_test, limit: 5, avg_job_duration: 15 }

      before { 15.times { |a_jid| strategy.throttled? a_jid } }

      it "takes the explicit job duration into account" do
        expect(subject.retry_in(jid)).to be_within(1).of(10 * 15 / 5)
      end
    end

    context "when jobs that don't get subtracted backlog size because of a bug or something crashed" do
      before { 15.times { |a_jid| strategy.throttled? a_jid } }

      it "doesn't delay jobs forever" do
        Timecop.travel(Time.now + (24 * 60 * 60)) do
          expect(subject.retry_in(jid)).to eq 0
        end
      end
    end

    context "when limit not exceeded, because the oldest job was more than the ttl ago" do
      before do
        Timecop.travel(Time.now - 1000) do
          strategy.throttled? jid
        end
        4.times { strategy.throttled? jid }
      end

      it "tells us we do not need to wait" do
        expect(subject.retry_in(jid)).to eq 0
      end
    end

    context "when limit not exceeded, because there are fewer jobs than the limit" do
      before do
        4.times { strategy.throttled? jid }
      end

      it "tells us we do not need to wait" do
        expect(subject.retry_in(jid)).to eq 0
      end
    end

    context "when dynamic limit returns nil" do
      let(:strategy) { described_class.new :test, limit: proc { |*| } }

      before { 5.times { strategy.throttled? jid } }

      it "tells us we do not need to wait" do
        expect(subject.retry_in(jid)).to eq 0
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
      described_class.new :test, limit: 5, key_suffix: ->(i) { i }
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

      describe "when limit is 0" do
        let(:key_input) { initial_key_input }
        let(:strategy) { described_class.new :test, limit: 0 }

        it { is_expected.to be true }
      end

      describe "when limit is negative" do
        let(:key_input) { initial_key_input }
        let(:strategy) { described_class.new :test, limit: -5 }

        it { is_expected.to be true }
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
          expect(strategy.throttled?(jid, 456)).to be false
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
      described_class.new :test, limit: -> { 5 }
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
      let(:kwargs) { { limit: 5, key_suffix: -> { "xxx" } } }

      it { is_expected.to be_truthy }
    end

    describe "with a dynamic limit" do
      let(:kwargs) { { limit: -> { 5 } } }

      it { is_expected.to be_truthy }
    end

    describe "without a dynamic key suffix and static configration" do
      let(:kwargs) { { limit: 5 } }

      it { is_expected.to be_falsy }
    end
  end
end
