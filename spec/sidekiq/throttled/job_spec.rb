# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Job do
  let(:working_class) { Class.new { include Sidekiq::Throttled::Job } }

  it "aliased as Sidekiq::Throttled::Worker" do
    expect(Sidekiq::Throttled::Worker).to be described_class
  end

  describe ".sidekiq_throttle" do
    it "delegates call to Registry.register" do
      expect(Sidekiq::Throttled::Registry)
        .to receive(:add).with(working_class, :foo => :bar)

      working_class.sidekiq_throttle(:foo => :bar)
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
