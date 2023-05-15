# frozen_string_literal: true

require_relative "./job"

module Sidekiq
  module Throttled
    # A new module, Sidekiq::Job, was added in Sidekiq version 6.3.0 as a
    # simple alias for Sidekiq::Worker as the term "worker" was considered
    # too generic and confusing. Many people call a Sidekiq process a "worker"
    # whereas others call the thread that executes jobs a "worker".
    Worker = Job
  end
end
