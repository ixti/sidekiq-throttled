# frozen_string_literal: true

require "sidekiq/throttled/unit_of_work"

RSpec.describe Sidekiq::Throttled::UnitOfWork do
  describe "#queue"
  describe "#job"
  describe "#queue_name"
  describe "#requeue"
end
