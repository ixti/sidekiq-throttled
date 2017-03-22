# frozen_string_literal: true

require "rack/test"
require "capybara/rspec"

require "sidekiq/throttled/web"

require "support/working_class_hero"

RSpec.describe Sidekiq::Throttled::Web, :sidekiq => :enabled do
  before do
    Sidekiq::Throttled.setup!

    Sidekiq::Client.push({
      "class" => WorkingClassHero,
      "queue" => "foo",
      "args"  => [[]]
    })

    Sidekiq::Client.push({
      "class" => WorkingClassHero,
      "queue" => "bar",
      "args"  => [[]]
    })

    pauser.pause! "foo"
  end

  let(:pauser) { Sidekiq::Throttled::QueuesPauser.instance }

  describe "mounted app" do
    include Rack::Test::Methods

    def app
      Sidekiq::Web
    end

    describe "GET /" do
      before { get "/" }
      specify { expect(last_response.status).to eq 200 }
      specify { expect(last_response.body).to include "Pauser" }
    end

    describe "GET /pauser" do
      before { get "/pauser" }

      specify { expect(last_response.status).to eq 200 }

      specify { expect(last_response.body).to include "foo" }
      specify { expect(last_response.body).to include "bar" }
    end

    describe "POST /pauser/:queue" do
      it "allows pausing the queue" do
        expect(pauser).to receive(:pause!).with("xxx")
        post "/pauser/xxx", :action => "pause"
      end

      it "allows resuming the queue" do
        expect(pauser).to receive(:resume!).with("xxx")
        post "/pauser/xxx", :action => "resume"
      end
    end
  end

  describe "Pauser UI", :type => :feature do
    before { Capybara.app = Sidekiq::Web }

    it "allows resuming paused queues" do
      visit "/pauser"

      expect(pauser).to receive(:resume!).with("foo").and_call_original

      find_link(:href => "/queues/foo").find(:xpath, "../..")
        .click_button("Resume")

      expect(find_link(:href => "/queues/foo").find(:xpath, "../.."))
        .to have_button("Pause")
    end

    it "allows pausing queues" do
      visit "/pauser"

      expect(pauser).to receive(:pause!).with("bar").and_call_original

      find_link(:href => "/queues/bar").find(:xpath, "../..")
        .click_button("Pause")

      expect(find_link(:href => "/queues/bar").find(:xpath, "../.."))
        .to have_button("Resume")
    end
  end
end
