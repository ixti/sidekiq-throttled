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

      expect(working_class.sidekiq_throttled_requeue_options).to eq({ with: :enqueue })
    end

    it "accepts and stores a requeue parameter including :with" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, foo: :bar)

      working_class.sidekiq_throttle(foo: :bar, requeue: { with: :schedule })

      expect(working_class.sidekiq_throttled_requeue_options).to eq({ with: :schedule })
    end

    it "accepts and stores a requeue parameter including :to" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, foo: :bar)

      working_class.sidekiq_throttle(foo: :bar, requeue: { to: :other_queue })

      expect(working_class.sidekiq_throttled_requeue_options).to eq({ to: :other_queue, with: :enqueue })
    end

    it "accepts and stores a requeue parameter including both :to and :with" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, foo: :bar)

      working_class.sidekiq_throttle(foo: :bar, requeue: { to: :other_queue, with: :schedule })

      expect(working_class.sidekiq_throttled_requeue_options).to eq({ to: :other_queue, with: :schedule })
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
        expect(Sidekiq::Throttled::Registry)
          .to receive(:add).with(working_class, foo: :bar)

        working_class.sidekiq_throttle(foo: :bar)

        expect(working_class.sidekiq_throttled_requeue_options).to eq({ with: :schedule })
      end

      it "uses the default alongside a requeue parameter including :to" do
        expect(Sidekiq::Throttled::Registry)
          .to receive(:add).with(working_class, foo: :bar)

        working_class.sidekiq_throttle(foo: :bar, requeue: { to: :other_queue })

        expect(working_class.sidekiq_throttled_requeue_options).to eq({ to: :other_queue, with: :schedule })
      end

      it "allows overriding the default" do
        expect(Sidekiq::Throttled::Registry)
          .to receive(:add).with(working_class, foo: :bar)

        working_class.sidekiq_throttle(foo: :bar, requeue: { with: :enqueue })

        expect(working_class.sidekiq_throttled_requeue_options).to eq({ with: :enqueue })
      end

      it "allows overriding the default and including a :to parameter" do
        expect(Sidekiq::Throttled::Registry)
          .to receive(:add).with(working_class, foo: :bar)

        working_class.sidekiq_throttle(foo: :bar, requeue: { to: :other_queue, with: :enqueue })

        expect(working_class.sidekiq_throttled_requeue_options).to eq({ to: :other_queue, with: :enqueue })
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
