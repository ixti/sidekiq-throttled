# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::StrategyCollection do
  let(:collection) { described_class.new(strategies, **options) }

  let(:options) do
    {
      strategy:   Sidekiq::Throttled::Strategy::Concurrency,
      name:       "test",
      key_suffix: nil
    }
  end

  describe "#initialize" do
    context "with no strategies" do
      let(:strategies) { nil }

      it { expect(collection.count).to eq 0 }
    end

    context "with one strategy as a Hash" do
      let(:strategies) do
        { limit: 1, key_suffix: ->(proj_id) { proj_id } }
      end

      it { expect(collection.count).to eq 1 }
    end

    context "with couple of strategies as an array" do
      let(:strategies) do
        [
          { limit: 1, key_suffix: ->(_proj_id, user_id) { user_id } },
          { limit: 10, key_suffix: ->(proj_id, _user_id) { proj_id } }
        ]
      end

      it { expect(collection.count).to eq 2 }
    end
  end

  describe "#dynamic?" do
    subject { collection.dynamic? }

    context "with no dynamic strategy" do
      let(:strategies) { { limit: 5 } }

      it { is_expected.to be false }
    end

    context "with one dynamic strategy" do
      let(:strategies) do
        [
          { limit: 1, key_suffix: ->(_project_id, user_id) { user_id } },
          { limit: 10 }
        ]
      end

      it { is_expected.to be true }
    end
  end

  describe "#throttled?" do
    subject(:throttled?) { collection.throttled?(*args) }

    let(:args) { [jid, 11, 22] }

    let(:strategies) do
      [
        { limit: 1, key_suffix: ->(_project_id, user_id) { user_id } },
        { limit: 10 }
      ]
    end

    context "with no throttled strategies" do
      it do
        allow(collection.strategies[0]).to receive(:throttled?).with(*args).and_return(false)
        allow(collection.strategies[1]).to receive(:throttled?).with(*args).and_return(false)

        expect(throttled?).to be false
      end
    end

    context "with one strategy throttled" do
      it do
        allow(collection.strategies[0]).to receive(:throttled?).with(*args).and_return(false)
        allow(collection.strategies[1]).to receive(:throttled?).with(*args).and_return(true)

        expect(throttled?).to be true
      end
    end
  end

  describe '#retry_in' do
    let(:strategies) do
      [
        { limit: 1, key_suffix: ->(_project_id, user_id) { user_id } },
        { limit: 10 },
        { limit: 30 }
      ]
    end
    let(:job_id) { jid }

    it do
      collection.each_with_index do |s, i|
        allow(s).to receive(:retry_in).with(job_id, 11, 22).and_return(i * 10)
      end

      # Returns the max value from the strategies' retry_in returned values
      expect(collection.retry_in(job_id, 11, 22)).to eq 20
    end
  end

  describe "#finalize!" do
    subject(:finalize!) { collection.finalize!(job_id, *job_args) }

    let(:job_id) { jid }
    let(:job_args) { [11, 22] }

    let(:strategies) do
      [
        { limit: 1, key_suffix: ->(_project_id, user_id) { user_id } },
        { limit: 10 }
      ]
    end

    it do
      expect(collection.strategies).to all(
        receive(:finalize!).with(job_id, *job_args)
      )

      finalize!
    end
  end

  describe "#reset!" do
    subject(:reset!) { collection.reset! }

    let(:strategies) do
      [
        { limit: 1, key_suffix: ->(_project_id, user_id) { user_id } },
        { limit: 10 }
      ]
    end

    it do
      expect(collection.strategies).to all(receive(:reset!))
      reset!
    end
  end
end
