# frozen_string_literal: true

module Sidekiq
  module Throttled
    module Utils
      module_function

      # Resolve constant from it's name
      # @param name [#to_s] Constant name
      # @return [Object, nil] Resolved constant or nil if failed.
      def constantize(name)
        name.to_s.sub(/^::/, "").split("::").inject(Object, &:const_get)
      rescue NameError
        Sidekiq.logger.warn { "Failed to constantize: #{name}" }
        nil
      end
    end
  end
end
