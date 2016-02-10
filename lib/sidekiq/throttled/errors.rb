# frozen_string_literal: true
module Sidekiq
  module Throttled
    # Generic class for Sidekiq::Throttled errors
    class Error < StandardError; end
  end
end
