# frozen_string_literal: true

require "timecop"

# Prohibit use of block-less API
Timecop.safe_mode = true

RSpec.configure do |config|
  config.around :example do |example|
    meta = example.metadata[:time]
    next example.call unless meta

    handler = Array(meta).inject example do |a, (k, v)|
      case k
      when :freeze, :frozen
        v ||= Time.now.utc
        proc { Timecop.freeze(v, &a) }
      when :travel
        raise "You must specify time to travel to" unless v
        proc { Timecop.travel(v, &a) }
      when :scale
        raise "You must specify scale of a second" unless v
        proc { Timecop.scale(v, &a) }
      else
        raise "Unexpected timecop mode: #{k.inspect}"
      end
    end

    handler.call
  end
end
