# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Communicator do
  subject(:communicator) { described_class.instance }

  let(:callbacks) { described_class::Callbacks.new }

  around do |example|
    begin
      old_callbacks = communicator.instance_variable_get(:@callbacks)
      old_listener  = communicator.instance_variable_get(:@listener)

      communicator.instance_variable_set(:@callbacks, callbacks)
      communicator.instance_variable_set(:@listener,  nil)

      example.run
    ensure
      communicator.stop_listener

      communicator.instance_variable_set(:@callbacks, old_callbacks)
      communicator.instance_variable_set(:@listener,  old_listener)
    end
  end

  def run_callbacks(name, *args)
    callbacks.instance_variable_get(:@handlers).fetch(name).each do |b|
      b.call(*args)
    end
  end

  describe "#start_listener" do
    it "starts Listener" do
      expect(Sidekiq::Throttled::Communicator::Listener)
        .to receive(:new).with(String, callbacks)
        .and_call_original

      communicator.start_listener
    end
  end

  describe "#stop_listener" do
    it "stops Listener" do
      listener = instance_double Sidekiq::Throttled::Communicator::Listener

      allow(Sidekiq::Throttled::Communicator::Listener)
        .to receive(:new).and_return listener
      communicator.start_listener

      expect(listener).to receive(:stop)
      communicator.stop_listener
    end
  end

  describe "#setup!" do
    before do
      allow(Sidekiq).to receive(:server?).and_return true
      communicator.setup!
    end

    after do
      %i[startup quiet].each do |event|
        Sidekiq.options[:lifecycle_events][event].clear
      end
    end

    it "assigns #start_listener to `:startup` Sidekiq event" do
      expect(communicator).to receive(:start_listener).at_least(:once)
      Sidekiq.options[:lifecycle_events][:startup].each(&:call)
    end

    it "assigns #stop_listener to `:quiet` Sidekiq event" do
      expect(communicator).to receive(:stop_listener).at_least(:once)
      Sidekiq.options[:lifecycle_events][:quiet].each(&:call)
    end
  end

  describe "#transmit" do
    it "transmits messages to listeners" do
      Sidekiq.redis do |conn|
        expect(conn)
          .to receive(:publish)
          .with("sidekiq:throttled", Marshal.dump(["xxx", nil]))
          .and_call_original

        communicator.transmit(conn, "xxx")
      end
    end
  end

  describe "#receive" do
    it "registers `message:{message}` event handler" do
      spy = double

      expect(callbacks).to receive(:on).with("message:xxx").and_call_original
      expect(spy).to receive(:touch)

      communicator.receive(:xxx) { spy.touch }
      run_callbacks "message:xxx"
    end
  end

  describe "#ready" do
    it "registers `ready` event handler" do
      spy = double

      expect(callbacks).to receive(:on).with("ready").and_call_original
      expect(spy).to receive(:touch)

      communicator.ready { spy.touch }
      run_callbacks "ready"
    end

    context "when listener already in ready state" do
      before do
        allow(communicator.start_listener).to receive(:ready?).and_return(true)
      end

      it "registers `ready` event handler and yields control to handler" do
        spy = double

        expect(callbacks).to receive(:on).with("ready").and_call_original
        expect(spy).to receive(:touch)

        communicator.ready { spy.touch }
      end
    end
  end
end
