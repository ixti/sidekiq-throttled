require 'sidekiq'
require 'sidekiq/version'

module Sidekiq
  module Throttled
    class Communicator
      if Sidekiq::VERSION >= '6.5.0'
        module ExceptionHandler
          def handle_exception(ex, ctx = {})
            Sidekiq.handle_exception(ex, ctx = {})
          end
        end

        # NOTE `Sidekiq.default_error_handler` is private API
        Sidekiq.error_handlers << Sidekiq.method(:default_error_handler)
      else
        require 'sidekiq/exception_handler'

        ExceptionHandler = ::Sidekiq::ExceptionHandler
      end
    end
  end
end
