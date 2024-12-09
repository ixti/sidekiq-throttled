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
        .to receive(:add).with(working_class, concurrency: { limit: 10 })

      working_class.sidekiq_throttle(concurrency: { limit: 10 })
    end

    it "accepts and registers a strategy with a requeue parameter including :with" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, concurrency: { limit: 10 }, requeue: { with: :schedule })

      working_class.sidekiq_throttle(concurrency: { limit: 10 }, requeue: { with: :schedule })
    end

    it "accepts and registers a strategy with a requeue parameter including :to" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, concurrency: { limit: 10 }, requeue: { to: :other_queue })

      working_class.sidekiq_throttle(concurrency: { limit: 10 }, requeue: { to: :other_queue })
    end

    it "accepts and registers a strategy with a requeue parameter including both :to and :with" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, concurrency: { limit: 10 },
          requeue: { to: :other_queue, with: :schedule })

      working_class.sidekiq_throttle(concurrency: { limit: 10 }, requeue: { to: :other_queue, with: :schedule })
    end

    it "raises an error when :with is not a valid value" do
      expect do
        working_class.sidekiq_throttle(requeue: { with: :invalid_with_value })
      end.to raise_error(ArgumentError, "requeue: invalid_with_value is not a valid value for :with")
    end

    context "when default_requeue_options are set" do
      before do
        Sidekiq::Throttled.configure do |config|
          config.default_requeue_options = { with: :schedule }
        end
      end

      after do
        Sidekiq::Throttled.configure(&:reset!)
      end

      it "uses the default when not overridden" do
        working_class.sidekiq_throttle(concurrency: { limit: 10 })

        strategy = Sidekiq::Throttled::Registry.get(working_class)
        expect(strategy.requeue_options).to eq({ with: :schedule })
      end

      it "uses the default alongside a requeue parameter including :to" do
        working_class.sidekiq_throttle(concurrency: { limit: 10 }, requeue: { to: :other_queue })

        strategy = Sidekiq::Throttled::Registry.get(working_class)
        expect(strategy.requeue_options).to eq({ to: :other_queue, with: :schedule })
      end

      it "allows overriding the default" do
        working_class.sidekiq_throttle(concurrency: { limit: 10 }, requeue: { with: :enqueue })

        strategy = Sidekiq::Throttled::Registry.get(working_class)
        expect(strategy.requeue_options).to eq({ with: :enqueue })
      end

      it "allows overriding the default and including a :to parameter" do
        working_class.sidekiq_throttle(concurrency: { limit: 10 }, requeue: { to: :other_queue, with: :enqueue })

        strategy = Sidekiq::Throttled::Registry.get(working_class)
        expect(strategy.requeue_options).to eq({ to: :other_queue, with: :enqueue })
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
