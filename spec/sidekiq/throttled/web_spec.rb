require "rack/test"

require "sidekiq/throttled/web"

RSpec.describe Sidekiq::Throttled::Web do
  include Rack::Test::Methods

  def app
    Sidekiq::Web
  end

  before do
    Sidekiq::Throttled::Registry.add "foo",
      :concurrency => { :limit => 5 }

    Sidekiq::Throttled::Registry.add "bar",
      :threshold => { :limit => 5, :period => 10 }

    3.times { Sidekiq::Throttled::Registry.get("foo").throttled? jid }
    3.times { Sidekiq::Throttled::Registry.get("bar").throttled? jid }
  end

  describe "GET /" do
    before { get "/" }

    specify { expect(last_response.status).to eq 200 }
    specify { expect(last_response.body).to include "Throttled" }
    specify { expect(last_response.body).to include "throttled" }
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

  describe "DELETE /throttled/:id" do
    context "when id is unknown" do
      it "does not fail" do
        delete "/throttled/abc"
        expect(last_response.status).to eq 302
      end
    end

    context "when id is known" do
      it "does not fail" do
        delete "/throttled/foo"
        expect(last_response.status).to eq 302
      end

      it "calls #reset! on matchin strategy" do
        strategy = Sidekiq::Throttled::Registry.get "foo"
        expect(strategy).to receive(:reset!)

        delete "/throttled/foo"
      end
    end
  end
end
