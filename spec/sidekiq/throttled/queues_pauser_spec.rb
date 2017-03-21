# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::QueuesPauser do
  subject(:pauser) { described_class.instance }

  let(:communicator) { Sidekiq::Throttled::Communicator.instance }

  describe "#setup!" do
    before { allow(Sidekiq).to receive(:server?).and_return true }

    let(:paused_queues) { pauser.instance_variable_get :@paused_queues }

    it "adds paused queue to the paused list" do
      paused_queues.replace %w(queue:xxx queue:yyy)

      expect(communicator).to receive(:receive).twice do |event, &block|
        block.call "zzz" if "pause" == event
      end

      pauser.setup!

      expect(paused_queues).to eq Set.new(%w(queue:xxx queue:yyy queue:zzz))
    end

    it "removes resumed queue from paused list" do
      paused_queues.replace %w(queue:xxx queue:yyy)

      expect(communicator).to receive(:receive).twice do |event, &block|
        block.call "yyy" if "resume" == event
      end

      pauser.setup!

      expect(paused_queues).to eq Set.new(%w(queue:xxx))
    end

    it "resets paused queues each time communicator becomes ready" do
      paused_queues << "garbage"

      expect(communicator).to receive(:ready) do |&block|
        expect(pauser)
          .to receive(:paused_queues)
          .and_return(%w(foo bar))

        block.call
        expect(paused_queues).to eq Set.new(%w(queue:foo queue:bar))
      end

      pauser.setup!
    end
  end

  describe "#filter" do
    it "returns list without paused queues" do
      queues = %w(queue:xxx queue:yyy queue:zzz)
      paused = Set.new %w(queue:yyy queue:zzz)

      pauser.instance_variable_set(:@paused_queues, paused)
      expect(pauser.filter(queues)).to eq %w(queue:xxx)
    end
  end

  describe "#paused_queues" do
    it "returns list of paused quques" do
      %w(foo bar).each { |q| pauser.pause! q }
      expect(pauser.paused_queues).to match_array %w(foo bar)
    end

    it "fetches list from redis" do
      Sidekiq.redis do |conn|
        expect(conn)
          .to receive(:smembers).with("throttled:X:paused_queues")
          .and_call_original

        pauser.paused_queues
      end
    end
  end

  describe "#pause!" do
    it "normalizes given queue name" do
      expect(Sidekiq::Throttled::QueueName)
        .to receive(:normalize).with("foo:bar")
        .and_call_original

      pauser.pause! "foo:bar"
    end

    it "pushes normalized queue name to the paused queues list" do
      Sidekiq.redis do |conn|
        expect(conn)
          .to receive(:sadd).with("throttled:X:paused_queues", "xxx")
          .and_call_original

        pauser.pause! "foo:bar:queue:xxx"
      end
    end

    it "sends notification over communicator" do
      Sidekiq.redis do |conn|
        expect(communicator)
          .to receive(:transmit).with(conn, "pause", "xxx")
          .and_call_original

        pauser.pause! "foo:bar:queue:xxx"
      end
    end
  end

  describe "#paused?" do
    before { pauser.pause! "xxx" }

    it "normalizes given queue name" do
      expect(Sidekiq::Throttled::QueueName)
        .to receive(:normalize).with("xxx")
        .and_call_original

      pauser.paused? "xxx"
    end

    context "for paused queue" do
      subject { pauser.paused? "xxx" }
      it { is_expected.to be true }
    end

    context "for non-paused queue" do
      subject { pauser.paused? "yyy" }
      it { is_expected.to be false }
    end
  end

  describe "#resume!" do
    it "normalizes given queue name" do
      expect(Sidekiq::Throttled::QueueName)
        .to receive(:normalize).with("foo:bar")
        .and_call_original

      pauser.resume! "foo:bar"
    end

    it "pushes normalized queue name to the paused queues list" do
      Sidekiq.redis do |conn|
        expect(conn)
          .to receive(:srem).with("throttled:X:paused_queues", "xxx")
          .and_call_original

        pauser.resume! "foo:bar:queue:xxx"
      end
    end

    it "sends notification over communicator" do
      Sidekiq.redis do |conn|
        expect(communicator)
          .to receive(:transmit).with(conn, "resume", "xxx")
          .and_call_original

        pauser.resume! "foo:bar:queue:xxx"
      end
    end
  end
end
