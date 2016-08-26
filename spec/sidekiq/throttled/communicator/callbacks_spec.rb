# frozen_string_literal: true

require "support/logging"

RSpec.describe Sidekiq::Throttled::Communicator::Callbacks do
  subject(:callbacks) { described_class.new }

  describe "#on" do
    it "fails if no block given" do
      expect { callbacks.on("foo") }
        .to raise_error(ArgumentError, "No block given")
    end

    it "normalized given name" do
      proc_spy = proc { nil }
      payload  = double

      expect(proc_spy).to receive(:call).with(payload)

      callbacks.on(:foo, &proc_spy)
      callbacks.run("foo", payload)
    end
  end

  describe "#run" do
    it "normalized given name" do
      proc_spy = proc { nil }
      payload  = double

      expect(proc_spy).to receive(:call).with(payload)

      callbacks.on("foo", &proc_spy)
      callbacks.run(:foo, payload)
    end

    it "runs handlers in separate thread" do
      Thread.current[:context] = 1

      callbacks.on("xxx") { expect(Thread.current[:context]).to be nil }

      thread = Thread.new do
        Thread.current[:context] = 2
        callbacks.run("xxx")
      end

      thread.join
    end

    it "ignores unregistered events" do
      expect { callbacks.run("xxx") }.not_to raise_error
    end

    context "when handler fails with StandardError" do
      it "does not interrupts callback execution upon StandardError" do
        spy = double

        callbacks.on("xxx") { raise StandardError }
        callbacks.on("xxx") { spy.touch }
        callbacks.on("xxx") { raise StandardError }

        expect(spy).to receive(:touch).once
        expect { callbacks.run("xxx") }.not_to raise_error
      end

      it "logs failure" do
        callbacks.on("xxx") { raise "boom" }
        callbacks.run("xxx")

        log = Sidekiq::Logging.logger.output

        expect(log).to include("RuntimeError: boom")
      end
    end

    context "when handler fails with Sidekiq::Shutdown" do
      it "not handled" do
        spy = double

        callbacks.on("xxx") { raise Sidekiq::Shutdown }
        callbacks.on("xxx") { spy.touch }
        callbacks.on("xxx") { raise Sidekiq::Shutdown }

        expect(spy).not_to receive(:touch)
        expect { callbacks.run("xxx") }.to raise_error(Sidekiq::Shutdown)
      end
    end

    context "when handler fails with Exception" do
      it "not handled" do
        spy = double

        callbacks.on("xxx") { raise Exception }
        callbacks.on("xxx") { spy.touch }
        callbacks.on("xxx") { raise Exception }

        expect(spy).not_to receive(:touch)
        expect { callbacks.run("xxx") }.to raise_error(Exception)
      end
    end
  end
end
