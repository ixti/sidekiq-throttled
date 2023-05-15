# frozen_string_literal: true

require_relative "./basic_fetch"

module Sidekiq
  module Throttled
    # @deprecated Use Sidekiq::Throttled::BasicFetch
    Fetch = BasicFetch
  end
end
