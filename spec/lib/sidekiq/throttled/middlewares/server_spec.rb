# frozen_string_literal: true

require "sidekiq/throttled/middlewares/server"

RSpec.describe Sidekiq::Throttled::Middlewares::Server do
  subject(:middleware) { described_class.new }

  describe "#call" do
    let(:args) { ["bar", 1] }
    let(:payload) { { "class" => "foo", "jid" => "bar" } }
    let(:payload_args) { { "class" => "foo", "jid" => "bar", "args" => args } }

    context "when job class has strategy with concurrency constraint" do
      let! :strategy do
        Sidekiq::Throttled::Registry.add payload["class"],
          concurrency: { limit: 1 }
      end

      it "calls #finalize! of queue with jid of job being processed" do
        expect(strategy).to receive(:finalize!).with "bar"
        middleware.call(double, payload, double) { |*| :foobar }
      end

      it "calls #finalize! of queue with jid and args of job being processed" do
        expect(strategy).to receive(:finalize!).with "bar", *args
        middleware.call(double, payload_args, double) { |*| :foobar }
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
      let(:payload_args) do
        {
          "class"   => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
          "wrapped" => "wrapped-foo",
          "args"    => [{ "job_class" => "foo", "arguments" => args }],
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

      it "calls #finalize! of queue with jid and args of job being processed" do
        expect(strategy).to receive(:finalize!).with "bar", *args
        middleware.call(double, payload_args, double) { |*| :foobar }
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

    context "when message has no strategy keys but worker has multiple configured keys" do
      let(:payload) { { "class" => "MultiStrategyFinalizeJob", "jid" => "bar", "args" => args } }
      let(:strategies) do
        first_key = "first-#{jid}"
        second_key = "second-#{jid}"

        {
          first:      Sidekiq::Throttled::Registry.add(first_key, concurrency: { limit: 1 }),
          second:     Sidekiq::Throttled::Registry.add(second_key, concurrency: { limit: 1 }),
          first_key:  first_key,
          second_key: second_key
        }
      end

      before do
        local_first_key = strategies.fetch(:first_key)
        local_second_key = strategies.fetch(:second_key)

        stub_job_class("MultiStrategyFinalizeJob") do
          sidekiq_throttle_as local_first_key, local_second_key
        end
      end

      it "finalizes every configured strategy" do
        expect(strategies.fetch(:first)).to receive(:finalize!).with("bar", *args)
        expect(strategies.fetch(:second)).to receive(:finalize!).with("bar", *args)

        middleware.call(double, payload, double) { |*| :foobar }
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

    context "when message contains no job class" do
      before do
        allow(Sidekiq::Throttled::Registry).to receive(:get).and_call_original
        payload.delete("class")
      end

      it "does not attempt to retrieve any strategy" do
        expect { |b| middleware.call(double, payload, double, &b) }.to yield_control

        expect(Sidekiq::Throttled::Registry).not_to receive(:get)
      end
    end

    context "when message contains no jid" do
      before do
        allow(Sidekiq::Throttled::Registry).to receive(:get).and_call_original
        payload.delete("jid")
      end

      it "does not attempt to retrieve any strategy" do
        expect { |b| middleware.call(double, payload, double, &b) }.to yield_control

        expect(Sidekiq::Throttled::Registry).not_to receive(:get)
      end
    end
  end
end
