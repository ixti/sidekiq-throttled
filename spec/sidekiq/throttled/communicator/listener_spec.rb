# frozen_string_literal: true

require "json"
require "support/logging"

RSpec.describe Sidekiq::Throttled::Communicator::Listener do
  subject(:listener) { described_class.new("sidekiq:throttled", callbacks) }

  # send SIGKILL to listener thread at the end
  after { listener.stop }

  let :callbacks do
    Class.new Array do
      def run(*args)
        self << args.to_json
      end
    end.new
  end

  def wait_for_listener_to_stop_running
    prev_delay = 0.0
    curr_delay = 0.1

    42.times do
      listener.run if listener.alive?

      sleep curr_delay

      return if listener.stop?

      next_delay = prev_delay + curr_delay
      prev_delay = curr_delay
      curr_delay = next_delay
    end
  end

  def send_message(*args)
    Sidekiq.redis do |conn|
      Sidekiq::Throttled::Communicator.instance.transmit(conn, *args)
    end

    wait_for_listener_to_stop_running
  end

  describe "#stop" do
    it "stops listener" do
      listener.stop
      wait_for_listener_to_stop_running
      expect(listener).not_to be_alive
    end
  end

  it { is_expected.to be_a Thread }

  it "runs `ready` callbacks when listener subscribed" do
    wait_for_listener_to_stop_running
    expect(callbacks).to match_array %w(["ready"])
  end

  it "runs `message:{message}` callbacks upon messages" do
    wait_for_listener_to_stop_running

    send_message("a", "xxx")
    send_message("b")

    wait_for_listener_to_stop_running
    expect(callbacks).to match_array %w(
      ["ready"]
      ["message:a","xxx"]
      ["message:b",null]
    )
  end

  it "is running once being initialized" do
    wait_for_listener_to_stop_running
    expect(listener).to be_listening
  end

  it "stops listener upon Sidekiq::Shutdown being raised" do
    wait_for_listener_to_stop_running
    listener.raise Sidekiq::Shutdown
    3.times { wait_for_listener_to_stop_running }

    expect(listener).not_to be_ready
    expect(listener).not_to be_listening
  end

  context "when listener receives StandardError" do
    before do
      wait_for_listener_to_stop_running
      listener.raise StandardError, "Oops, I did it again..."
      3.times { wait_for_listener_to_stop_running }
    end

    it "logs exception occurence" do
      expect(Sidekiq::Logging.logger.output)
        .to include "StandardError: Oops, I did it again..."
    end

    it "restarts listen loop" do
      expect(listener).to be_ready
      expect(listener).to be_listening
    end

    it "re-emits `ready` event once re-subscribed" do
      expect(callbacks).to match_array %w(
        ["ready"]
        ["ready"]
      )
    end
  end

  context "when listener receives unrecoverable Exception" do
    before do
      wait_for_listener_to_stop_running
      listener.raise Exception, "die!!!"
      3.times { wait_for_listener_to_stop_running }
    end

    it "logs exception occurence" do
      expect(Sidekiq::Logging.logger.output).to include "Exception: die!!!"
    end

    it "does not recovers" do
      expect(listener).not_to be_ready
      expect(listener).not_to be_listening
    end
  end
end
