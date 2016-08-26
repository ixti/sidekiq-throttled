# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::QueueName do
  let(:queue_name) { described_class }

  describe ".normalize" do
    it "removes `queue:` prefix" do
      expect(queue_name.normalize("queue:xxx")).to eq("xxx")
    end

    it "removes any possible extra prefixes (namespaces)" do
      expect(queue_name.normalize("foo:bar:queue:queue:xxx")).to eq("xxx")
    end
  end

  describe ".expand" do
    it "prepends `queue:` prefix" do
      expect(queue_name.expand("xxx")).to eq("queue:xxx")
    end

    it "does not normalized given name" do
      expect(queue_name.expand("queue:xxx")).to eq("queue:queue:xxx")
    end
  end
end
