# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Job do
  let(:working_class) do
    Class.new do
      include Sidekiq::Job
      include Sidekiq::Throttled::Job
    end
  end

  it "aliased as Sidekiq::Throttled::Worker" do
    expect(Sidekiq::Throttled::Worker).to be described_class
  end

  describe ".sidekiq_throttle" do
    it "delegates call to Registry.register" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, foo: :bar)

      working_class.sidekiq_throttle(foo: :bar)

      expect(working_class.sidekiq_throttled_requeue_with).to eq :enqueue
    end

    it "accepts and stores a requeue_with parameter" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, foo: :bar)

      working_class.sidekiq_throttle(foo: :bar, requeue_with: :schedule)

      expect(working_class.sidekiq_throttled_requeue_with).to eq :schedule
    end

    context "when a default_requeue_with is set" do
      before { Sidekiq::Throttled.configuration.default_requeue_with = :schedule }

      after { Sidekiq::Throttled.configuration.reset! }

      it "uses the default when not overridden" do
        expect(Sidekiq::Throttled::Registry)
          .to receive(:add).with(working_class, foo: :bar)

        working_class.sidekiq_throttle(foo: :bar)

        expect(working_class.sidekiq_throttled_requeue_with).to eq :schedule
      end

      it "allows overriding the default" do
        expect(Sidekiq::Throttled::Registry)
          .to receive(:add).with(working_class, foo: :bar)

        working_class.sidekiq_throttle(foo: :bar, requeue_with: :enqueue)

        expect(working_class.sidekiq_throttled_requeue_with).to eq :enqueue
      end
    end
  end

  describe ".sidekiq_throttle_as" do
    it "delegates call to Registry.register" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add_alias).with(working_class, :foobar)

      working_class.sidekiq_throttle_as :foobar
    end
  end
end
