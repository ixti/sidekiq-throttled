# frozen_string_literal: true

require_relative "./app"

require "rack/session"
require "securerandom"
require "sidekiq/web"
require "sidekiq/throttled/web"

File.open(".session.key", "w") { _1.write(SecureRandom.hex(32)) }
use Rack::Session::Cookie, secret: File.read(".session.key")

run Sidekiq::Web
