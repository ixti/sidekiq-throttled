# frozen_string_literal: true

require "rack/test"

require "sidekiq/throttled/web"

RSpec.describe Sidekiq::Throttled::Web do
  include Rack::Test::Methods

  def app
    Sidekiq::Web
  end

  it "shows standalone Enhanced Queues tab by default" do
    get "/"

    expect(last_response.body)
      .to include('<a href="/queues">Queues')
      .and include('<a href="/enhanced-queues">Enhanced Queues')
  end

  describe ".enhance_queues_tab!" do
    before { Sidekiq::Throttled::Web.enhance_queues_tab! }
    after { Sidekiq::Throttled::Web.restore_queues_tab! }

    it "replaces default Queues tab with Enhanced" do
      get "/"

      expect(last_response.body)
        .to include('<a href="/enhanced-queues">Queues')

      expect(last_response.body)
        .not_to include('<a href="/enhanced-queues">Enhanced Queues')
    end
  end
end
