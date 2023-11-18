# frozen_string_literal: true

require "sidekiq/throttled/cooldown"

RSpec.describe Sidekiq::Throttled::Cooldown do
  subject(:cooldown) { described_class.new(config) }

  let(:config) { Sidekiq::Throttled::Config.new }

  describe ".[]" do
    subject { described_class[config] }

    it { is_expected.to be_an_instance_of described_class }

    context "when `cooldown_period` is nil" do
      before { config.cooldown_period = nil }

      it { is_expected.to be_nil }
    end
  end

  describe "#notify_throttled" do
    before do
      config.cooldown_threshold = 5

      (config.cooldown_threshold - 1).times do
        cooldown.notify_throttled("queue:the_longest_line")
      end
    end

    it "marks queue for exclusion once threshold is met" do
      cooldown.notify_throttled("queue:the_longest_line")

      expect(cooldown.queues).to contain_exactly("queue:the_longest_line")
    end
  end

  describe "#notify_admitted" do
    before do
      config.cooldown_threshold = 5

      (config.cooldown_threshold - 1).times do
        cooldown.notify_throttled("queue:at_the_end_of")
        cooldown.notify_throttled("queue:the_longest_line")
      end
    end

    it "resets threshold counter" do
      cooldown.notify_admitted("queue:at_the_end_of")

      cooldown.notify_throttled("queue:at_the_end_of")
      cooldown.notify_throttled("queue:the_longest_line")

      expect(cooldown.queues).to contain_exactly("queue:the_longest_line")
    end
  end

  describe "#queues" do
    before do
      config.cooldown_period    = 1.0
      config.cooldown_threshold = 1
    end

    it "keeps queue in the exclusion list for the duration of cooldown_period" do
      monotonic_time = 0.0

      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { monotonic_time }

      cooldown.notify_throttled("queue:at_the_end_of")

      monotonic_time += 0.9
      cooldown.notify_throttled("queue:the_longest_line")

      expect(cooldown.queues).to contain_exactly("queue:at_the_end_of", "queue:the_longest_line")

      monotonic_time += 0.1
      expect(cooldown.queues).to contain_exactly("queue:the_longest_line")

      monotonic_time += 1.0
      expect(cooldown.queues).to be_empty
    end
  end
end
