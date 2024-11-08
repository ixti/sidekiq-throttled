# frozen_string_literal: true

require "sidekiq/throttled/config"

RSpec.describe Sidekiq::Throttled::Config do
  subject(:config) { described_class.new }

  describe "#cooldown_period" do
    subject { config.cooldown_period }

    it { is_expected.to eq 1.0 }
  end

  describe "#cooldown_period=" do
    it "updates #cooldown_period" do
      expect { config.cooldown_period = 42.0 }
        .to change(config, :cooldown_period).to(42.0)
    end

    it "allows setting value to `nil`" do
      expect { config.cooldown_period = nil }
        .to change(config, :cooldown_period).to(nil)
    end

    it "fails if given value is neither `NilClass` nor `Float`" do
      expect { config.cooldown_period = 42 }
        .to raise_error(TypeError, %r{unexpected type})
    end

    it "fails if given value is not positive" do
      expect { config.cooldown_period = 0.0 }
        .to raise_error(ArgumentError, %r{must be positive})
    end
  end

  describe "#cooldown_threshold" do
    subject { config.cooldown_threshold }

    it { is_expected.to eq 100 }
  end

  describe "#cooldown_threshold=" do
    it "updates #cooldown_threshold" do
      expect { config.cooldown_threshold = 42 }
        .to change(config, :cooldown_threshold).to(42)
    end

    it "fails if given value is not `Integer`" do
      expect { config.cooldown_threshold = 42.0 }
        .to raise_error(TypeError, %r{unexpected type})
    end

    it "fails if given value is not positive" do
      expect { config.cooldown_threshold = 0 }
        .to raise_error(ArgumentError, %r{must be positive})
    end
  end
end
