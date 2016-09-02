# frozen_string_literal: true

require "sidekiq/throttled/fetch/unit_of_work"

RSpec.describe Sidekiq::Throttled::Fetch::UnitOfWork do
  describe "#queue"
  describe "#job"
  describe "#queue_name"
  describe "#requeue"
  describe "#requeue_throttled"
  describe "#throttled?"
end
