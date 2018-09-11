# frozen_string_literal: true

require "rack/test"

require "sidekiq/throttled/web"

require "support/capybara"

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

  describe ".enhance_queues_tab!", :type => :feature do
    before { described_class.enhance_queues_tab! }

    after  { described_class.restore_queues_tab! }

    it "replaces default Queues tab with Enhanced in top navbar" do
      visit "/"

      expect(page)
        .to have_link(:href => "/enhanced-queues", :text => "Queues")

      expect(page)
        .not_to have_link(:href => "/queues", :text => "Queues")
    end

    it "replaces enqueued link with enhanced queues in summar bar", :js do
      visit "/"
      expect(page).not_to have_link(:href => "/queues")
    end
  end
end
