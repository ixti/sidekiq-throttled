# frozen_string_literal: true

require "rack/test"

require "sidekiq/throttled/web"

require "support/capybara"
require "support/working_class_hero"

RSpec.describe Sidekiq::Throttled::Web, :sidekiq => :enabled do
  before do
    Sidekiq::Throttled.setup!

    Sidekiq::Client.push({
      "class" => WorkingClassHero,
      "queue" => "xxx",
      "args"  => [[]]
    })

    Sidekiq::Client.push({
      "class" => WorkingClassHero,
      "queue" => "yyy",
      "args"  => [[]]
    })

    pauser.pause! "xxx"
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
      specify { expect(last_response.body).to include "Enhanced Queues" }
    end

    describe "GET /enhanced-queues" do
      before { get "/enhanced-queues" }

      specify { expect(last_response.status).to eq 200 }

      specify { expect(last_response.body).to include "xxx" }
      specify { expect(last_response.body).to include "yyy" }
    end

    describe "POST /enhanced-queues/:queue" do
      let(:csrf_token) { SecureRandom.base64(32) }

      before do
        env "rack.session", :csrf => csrf_token
      end

      it "allows pausing the queue" do
        expect(pauser).to receive(:pause!).with("xxx")
        post "/enhanced-queues/xxx", :action => "pause", :authenticity_token => csrf_token
      end

      it "allows resuming the queue" do
        expect(pauser).to receive(:resume!).with("xxx")
        post "/enhanced-queues/xxx", :action => "resume", :authenticity_token => csrf_token
      end

      it "allows deleting the queue" do
        expect(::Sidekiq::Queue.new("xxx").size).to be >= 1
        post "/enhanced-queues/xxx", :action => "delete", :authenticity_token => csrf_token
        expect(::Sidekiq::Queue.new("xxx").size).to eq 0
      end
    end
  end

  describe "Enhanced Queues UI", :type => :feature do
    it "allows resuming paused queues" do
      visit "/enhanced-queues"

      expect(pauser).to receive(:resume!).with("xxx").and_call_original

      find_link(:href => "/queues/xxx").find(:xpath, "../..")
        .click_button("Resume")

      expect(find_link(:href => "/queues/xxx").find(:xpath, "../.."))
        .to have_button("Pause")
    end

    it "allows pausing queues" do
      visit "/enhanced-queues"

      expect(pauser).to receive(:pause!).with("yyy").and_call_original

      find_link(:href => "/queues/yyy").find(:xpath, "../..")
        .click_button("Pause")

      expect(find_link(:href => "/queues/yyy").find(:xpath, "../.."))
        .to have_button("Resume")
    end

    it "allows deleting queues" do
      visit "/enhanced-queues"

      find_link(:href => "/queues/xxx").find(:xpath, "../..")
        .click_button("Delete")

      expect(page).not_to have_link(:href => "/queues/xxx")
    end
  end
end
