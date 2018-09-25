# frozen_string_literal: true

require "support/helpers/stub_class"

RSpec.describe Sidekiq::Throttled::Registry do
  let(:threshold)   { { :threshold => { :limit => 1, :period => 1 } } }
  let(:concurrency) { { :concurrency => { :limit => 1 } } }

  def capture_output
    old_stdout = $stdout
    old_stderr = $stderr

    $stdout = $stderr = StringIO.new

    yield

    $stdout.string
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end

  describe ".add" do
    let(:working_class) { double :to_s => "foo" }

    it "initializes new Strategy" do
      expect(Sidekiq::Throttled::Strategy)
        .to receive(:new).with("foo", threshold)

      described_class.add(working_class, threshold)
    end

    it "registers strategy with with it's #to_s name" do
      described_class.add(working_class, threshold)
      expect(described_class.get("foo")).to be_a Sidekiq::Throttled::Strategy
    end

    it "warns upon duplicate name given" do
      described_class.add(working_class, threshold)
      expect(capture_output { described_class.add(working_class, threshold) })
        .to include "Duplicate strategy name: foo"
    end
  end

  describe ".add_alias" do
    it "adds aliased name of rquested strategy" do
      existing_strategy = described_class.add(:foo, concurrency)
      described_class.add_alias(:bar, :foo)
      expect(described_class.get(:bar)).to be existing_strategy
    end

    it "warns upon duplicate name" do
      described_class.add(:foo, concurrency)
      described_class.add(:bar, concurrency)

      expect(capture_output { described_class.add_alias(:bar, :foo) })
        .to include "Duplicate strategy name: bar"
    end

    it "fails if there's no strategy registered with old name" do
      expect { described_class.add_alias(:bar, :foo) }
        .to raise_error "Strategy not found: foo"
    end
  end

  describe ".get" do
    subject { described_class.get name }

    let(:name) { "foo" }

    context "when strategy is not registered" do
      it { is_expected.to be nil }
    end

    context "when strategy was registered" do
      before { described_class.add(name, threshold) }

      it { is_expected.to be_a Sidekiq::Throttled::Strategy }
    end

    context "when strategy was registered on a parent class" do
      include RSpec::Helpers::StubClass

      let(:parent_class) { stub_class("Parent") }
      let(:child_class)  { stub_class("Child", parent_class) }

      let(:name) { child_class.name }

      before { described_class.add(parent_class.name, threshold) }

      it { is_expected.to be_a Sidekiq::Throttled::Strategy }
    end
  end

  describe ".each" do
    let(:names) { %w[foo bar baz] }

    before { names.each { |name| described_class.add(name, threshold) } }

    context "when no block given" do
      it "returns Enumerator" do
        expect(described_class.each).to be_an Enumerator
      end
    end

    context "when block given" do
      it "returns self instance" do
        expect(described_class.each { |*| }).to be described_class
      end

      it "yields control with each registered Strategy" do
        args = names.map { |n| [n, Sidekiq::Throttled::Strategy] }
        expect { |b| described_class.each(&b) }.to yield_successive_args(*args)
      end
    end

    it "does not includes aliases" do
      described_class.add_alias(:xyz, :foo)
      expect { |b| described_class.each(&b) }.to yield_control.exactly(3).times
    end
  end

  describe ".each_with_static_keys" do
    before do
      described_class.add("foo", threshold)
      described_class.add("bar", threshold.merge(:key_suffix => -> (i) { i }))
    end

    it "yields once for each strategy without dynamic key suffixes" do
      args = [["foo", Sidekiq::Throttled::Strategy]]
      expect do |b|
        described_class.each_with_static_keys(&b)
      end.to yield_successive_args(*args)
    end
  end
end
