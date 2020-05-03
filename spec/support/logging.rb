# frozen_string_literal: true

require "singleton"
require "logger"
require "stringio"

class PseudoLogger < Logger
  include Singleton

  def initialize
    @io = StringIO.new
    super(@io)
  end

  def reset!
    @io.reopen
  end

  def output
    @io.string
  end
end

if Sidekiq::VERSION < "6.0.0"
  Sidekiq::Logging.logger = PseudoLogger.instance
else
  Sidekiq.logger = PseudoLogger.instance
end

RSpec.configure do |config|
  config.after { PseudoLogger.instance.reset! }
end
