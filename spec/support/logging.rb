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

Sidekiq::Logging.logger = PseudoLogger.instance

RSpec.configure do |config|
  config.after { PseudoLogger.instance.reset! }
end
