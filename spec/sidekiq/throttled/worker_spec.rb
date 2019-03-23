# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Worker do
  let(:working_class) { Class.new { include Sidekiq::Throttled::Worker } }

  describe ".sidekiq_throttle" do
    context "without global_as argument" do
      it "delegates call to Registry.add" do
        expect(Sidekiq::Throttled::Registry)
          .to receive(:add).with(working_class, :foo => :bar)

        working_class.sidekiq_throttle(:foo => :bar)
      end
    end

    context "with global_as argument" do
      let(:args) { { :global_as => { :name => :global_throttle } } }
      let(:name) { args[:global_as][:name] }

      context "when the throttle is not registered yet" do
        before do
          allow(Sidekiq::Throttled::Registry).to receive(:get).and_return(false)
        end

        it "delegates call to Registry.add and calls .sidekiq_throttle_as" do
          expect(Sidekiq::Throttled::Registry)
            .to receive(:add).with(name, args)
          expect(working_class).to receive(:sidekiq_throttle_as).with(name)

          working_class.sidekiq_throttle(args)
        end
      end

      context "when the throttle is already registered" do
        before do
          allow(Sidekiq::Throttled::Registry).to receive(:get).and_return(true)
        end

        it "does not delegates and calls .sidekiq_throttle_as" do
          expect(Sidekiq::Throttled::Registry)
            .not_to receive(:add).with(working_class, args)
          expect(working_class).to receive(:sidekiq_throttle_as).with(name)

          working_class.sidekiq_throttle(args)
        end
      end
    end
  end

  describe ".sidekiq_throttle_as" do
    it "delegates call to Registry.add_alias" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add_alias).with(working_class, :foobar)

      working_class.sidekiq_throttle_as :foobar
    end
  end
end
