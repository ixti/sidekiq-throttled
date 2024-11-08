# frozen_string_literal: true

RSpec.describe Sidekiq::Throttled::Message do
  subject(:message) do
    described_class.new(item)
  end

  let(:item) do
    {
      "class" => "ExcitingJob",
      "args"  => [42],
      "jid"   => "deadbeef"
    }
  end

  describe "#job_class" do
    subject { message.job_class }

    it { is_expected.to eq("ExcitingJob") }

    context "with serialized payload" do
      let(:item) do
        JSON.dump({
          "class" => "ExcitingJob",
          "args"  => [42],
          "jid"   => "deadbeef"
        })
      end

      it { is_expected.to eq("ExcitingJob") }
    end

    context "with ActiveJob payload" do
      let(:item) do
        {
          "class"   => "ActiveJob",
          "wrapped" => "ExcitingJob",
          "args"    => [{ "arguments" => [42] }],
          "jid"     => "deadbeef"
        }
      end

      it { is_expected.to eq("ExcitingJob") }
    end

    context "with serialized ActiveJob payload" do
      let(:item) do
        JSON.dump({
          "class"   => "ActiveJob",
          "wrapped" => "ExcitingJob",
          "args"    => [{ "arguments" => [42] }],
          "jid"     => "deadbeef"
        })
      end

      it { is_expected.to eq("ExcitingJob") }
    end

    context "with invalid payload" do
      let(:item) { "invalid" }

      it { is_expected.to be nil }
    end

    context "with invalid serialized payload" do
      let(:item) { JSON.dump("invalid") }

      it { is_expected.to be nil }
    end
  end

  describe "#job_args" do
    subject { message.job_args }

    it { is_expected.to eq([42]) }

    context "with serialized payload" do
      let(:item) do
        JSON.dump({
          "class" => "ExcitingJob",
          "args"  => [42],
          "jid"   => "deadbeef"
        })
      end

      it { is_expected.to eq([42]) }
    end

    context "with ActiveJob payload" do
      let(:item) do
        {
          "class"   => "ActiveJob",
          "wrapped" => "ExcitingJob",
          "args"    => [{ "arguments" => [42] }],
          "jid"     => "deadbeef"
        }
      end

      it { is_expected.to eq([42]) }
    end

    context "with serialized ActiveJob payload" do
      let(:item) do
        JSON.dump({
          "class"   => "ActiveJob",
          "wrapped" => "ExcitingJob",
          "args"    => [{ "arguments" => [42] }],
          "jid"     => "deadbeef"
        })
      end

      it { is_expected.to eq([42]) }
    end

    context "with invalid payload" do
      let(:item) { "invalid" }

      it { is_expected.to be nil }
    end

    context "with invalid serialized payload" do
      let(:item) { JSON.dump("invalid") }

      it { is_expected.to be nil }
    end
  end

  describe "#job_id" do
    subject { message.job_id }

    it { is_expected.to eq("deadbeef") }

    context "with serialized payload" do
      let(:item) do
        JSON.dump({
          "class" => "ExcitingJob",
          "args"  => [42],
          "jid"   => "deadbeef"
        })
      end

      it { is_expected.to eq("deadbeef") }
    end

    context "with ActiveJob payload" do
      let(:item) do
        {
          "class"   => "ActiveJob",
          "wrapped" => "ExcitingJob",
          "args"    => [{ "arguments" => [42] }],
          "jid"     => "deadbeef"
        }
      end

      it { is_expected.to eq("deadbeef") }
    end

    context "with serialized ActiveJob payload" do
      let(:item) do
        JSON.dump({
          "class"   => "ActiveJob",
          "wrapped" => "ExcitingJob",
          "args"    => [{ "arguments" => [42] }],
          "jid"     => "deadbeef"
        })
      end

      it { is_expected.to eq("deadbeef") }
    end

    context "with invalid payload" do
      let(:item) { "invalid" }

      it { is_expected.to be nil }
    end

    context "with invalid serialized payload" do
      let(:item) { JSON.dump("invalid") }

      it { is_expected.to be nil }
    end
  end
end
