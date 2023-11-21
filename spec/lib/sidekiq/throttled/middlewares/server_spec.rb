# frozen_string_literal: true

require "sidekiq/throttled/middlewares/server"

RSpec.describe Sidekiq::Throttled::Middlewares::Server do
  subject(:middleware) { described_class.new }

  describe "#call" do
    let(:payload) { { "class" => "foo", "jid" => "bar" } }

    context "when job class has strategy with concurrency constraint" do
      let! :strategy do
        Sidekiq::Throttled::Registry.add payload["class"],
          concurrency: { limit: 1 }
      end

      it "calls #finalize! of queue with jid of job being processed" do
        expect(strategy).to receive(:finalize!).with "bar"
        middleware.call(double, payload, double) { |*| :foobar }
      end

      it "returns yields control to the given block" do
        expect { |b| middleware.call(double, payload, double, &b) }
          .to yield_control
      end

      it "returns result of given block" do
        expect(middleware.call(double, payload, double) { |*| :foobar })
          .to be :foobar
      end
    end

    context "when job class has strategy with concurrency constraint and uses ActiveJob" do
      let(:payload) do
        {
          "class"   => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
          "wrapped" => "wrapped-foo",
          "jid"     => "bar"
        }
      end

      let! :strategy do
        Sidekiq::Throttled::Registry.add payload["wrapped"],
          concurrency: { limit: 1 }
      end

      it "calls #finalize! of queue with jid of job being processed" do
        expect(strategy).to receive(:finalize!).with "bar"
        middleware.call(double, payload, double) { |*| :foobar }
      end

      it "returns yields control to the given block" do
        expect { |b| middleware.call(double, payload, double, &b) }
          .to yield_control
      end

      it "returns result of given block" do
        expect(middleware.call(double, payload, double) { |*| :foobar })
          .to be :foobar
      end
    end

    context "when job class has strategy without concurrency constraint" do
      let! :strategy do
        Sidekiq::Throttled::Registry.add payload["class"],
          threshold: { limit: 1, period: 1 }
      end

      it "calls #finalize! of queue with jid of job being processed" do
        expect(strategy).to receive(:finalize!).with "bar"
        middleware.call(double, payload, double) { |*| :foobar }
      end

      it "returns yields control to the given block" do
        expect { |b| middleware.call(double, payload, double, &b) }
          .to yield_control
      end

      it "returns result of given block" do
        expect(middleware.call(double, payload, double) { |*| :foobar })
          .to be :foobar
      end
    end

    context "when job class has no strategy" do
      it "returns yields control to the given block" do
        expect { |b| middleware.call(double, payload, double, &b) }
          .to yield_control
      end

      it "returns result of given block" do
        expect(middleware.call(double, payload, double) { |*| :foobar })
          .to be :foobar
      end
    end
  end
end
