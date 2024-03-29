# frozen_string_literal: true

require "capybara/rspec"
require "rack"

begin
  require "rack/session"
rescue LoadError
  # HACK: Sidekiq < 7.0.9 depends on rack ~> 2.0, and rack-session gem was
  #   part of rack gem at that era.
end

require "rack/test"
require "securerandom"

require "sidekiq/web"
require "sidekiq/throttled/web"

RSpec.describe Sidekiq::Throttled::Web do
  include Rack::Test::Methods

  def app
    @app ||= Rack::Builder.app do
      use Rack::Session::Cookie, secret: SecureRandom.hex(32), same_site: true
      run Sidekiq::Web
    end
  end

  def csrf_token
    SecureRandom.base64(Sidekiq::Web::CsrfProtection::TOKEN_LENGTH).tap do |csrf|
      env("rack.session", { csrf: csrf })
    end
  end

  before do
    Sidekiq::Throttled::Registry.add "foo",
      concurrency: { limit: 5 }

    Sidekiq::Throttled::Registry.add "bar",
      threshold: { limit: 5, period: 10 }

    3.times { Sidekiq::Throttled::Registry.get("foo").throttled? jid }
    3.times { Sidekiq::Throttled::Registry.get("bar").throttled? jid }
  end

  describe "GET /" do
    before { get "/" }

    specify { expect(last_response.status).to eq 200 }
    specify { expect(last_response.body).to include "Throttled" }
  end

  describe "GET /throttled" do
    before { get "/throttled" }

    specify { expect(last_response.status).to eq 200 }

    it "includes info about registered limiters" do
      Sidekiq::Throttled::Registry.each do |(name, _)|
        expect(last_response.body).to include name
      end
    end
  end

  describe "POST /throttled/:id/reset" do
    before do
      env "rack.session", csrf: csrf_token
    end

    context "when id is unknown" do
      it "does not fail" do
        post "/throttled/abc/reset", authenticity_token: csrf_token
        expect(last_response.status).to eq 302
      end
    end

    context "when id is known" do
      it "does not fail" do
        post "/throttled/foo/reset", authenticity_token: csrf_token
        expect(last_response.status).to eq 302
      end

      it "calls #reset! on matchin strategy" do
        strategy = Sidekiq::Throttled::Registry.get "foo"
        expect(strategy).to receive(:reset!)

        post "/throttled/foo/reset", authenticity_token: csrf_token
      end
    end
  end
end
