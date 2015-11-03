require "sidekiq/throttled/web/stats"

RSpec.describe Sidekiq::Throttled::Web::Stats do
  subject(:stats) { described_class.new strategy }

  describe "#to_html" do
    subject { stats.to_html }

    def label(level, count)
      %(<span class="label label-#{level}">#{count}</span>)
    end

    context "with nil strategy" do
      let(:strategy) { nil }
      it { is_expected.to eq "" }
    end

    context "with Concurrency strategy" do
      let :strategy do
        Sidekiq::Throttled::Strategy::Concurrency.new(:foo, :limit => 10)
      end

      it { is_expected.to start_with "10 jobs<br />" }
      it { is_expected.to end_with label("success", 0) }

      context "when less < 60 percents of limit exceeded" do
        before { 5.times { strategy.throttled? jid } }
        it { is_expected.to start_with "10 jobs<br />" }
        it { is_expected.to end_with label("success", 5) }
      end

      context "when less >= 60 and < 80 percents of limit exceeded" do
        before { 7.times { strategy.throttled? jid } }
        it { is_expected.to start_with "10 jobs<br />" }
        it { is_expected.to end_with label("warning", 7) }
      end

      context "when less >= 80 percents of limit exceeded" do
        before { 9.times { strategy.throttled? jid } }
        it { is_expected.to start_with "10 jobs<br />" }
        it { is_expected.to end_with label("danger", 9) }
      end
    end

    context "with Concurrency strategy" do
      let :strategy do
        Sidekiq::Throttled::Strategy::Threshold.new(:foo, {
          :limit  => 10,
          :period => 75
        })
      end

      it { is_expected.to start_with "10 jobs per 1 minute 15 seconds<br />" }
      it { is_expected.to end_with label("success", 0) }

      context "when less < 60 percents of limit exceeded" do
        before { 5.times { strategy.throttled? } }
        it { is_expected.to start_with "10 jobs per 1 minute 15 seconds<br />" }
        it { is_expected.to end_with label("success", 5) }
      end

      context "when less >= 60 and < 80 percents of limit exceeded" do
        before { 7.times { strategy.throttled? } }
        it { is_expected.to start_with "10 jobs per 1 minute 15 seconds<br />" }
        it { is_expected.to end_with label("warning", 7) }
      end

      context "when less >= 80 percents of limit exceeded" do
        before { 9.times { strategy.throttled? } }
        it { is_expected.to start_with "10 jobs per 1 minute 15 seconds<br />" }
        it { is_expected.to end_with label("danger", 9) }
      end
    end
  end
end
