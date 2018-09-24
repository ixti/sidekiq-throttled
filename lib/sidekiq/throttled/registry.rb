# frozen_string_literal: true

# internal
require "sidekiq/throttled/strategy"

module Sidekiq
  module Throttled
    # Registred strategies.
    #
    # @private
    module Registry
      @strategies = {}
      @aliases    = {}

      class << self
        # Adds strategy to the registry.
        #
        # @note prints a warning to STDERR upon duplicate strategy name
        # @param (see Strategy#initialize)
        # @return [Strategy]
        def add(name, **kwargs)
          name = name.to_s

          warn "Duplicate strategy name: #{name}" if @strategies[name]

          @strategies[name] = Strategy.new(name, **kwargs)
        end

        # Adds alias for existing strategy.
        #
        # @note prints a warning to STDERR upon duplicate strategy name
        # @param (#to_s) new_name
        # @param (#to_s) old_name
        # @raise [RuntimeError] if no strategy found with `old_name`
        # @return [Strategy]
        def add_alias(new_name, old_name)
          new_name = new_name.to_s
          old_name = old_name.to_s

          warn "Duplicate strategy name: #{new_name}" if @strategies[new_name]
          raise "Strategy not found: #{old_name}" unless @strategies[old_name]

          @aliases[new_name] = @strategies[old_name]
        end

        # @overload get(name)
        #   @param [#to_s] name
        #   @return [Strategy, nil] registred strategy
        #
        # @overload get(name, &block)
        #   Yields control to the block if requested strategy was found.
        #   @yieldparam [Strategy] strategy
        #   @yield [strategy] Gives found strategy to the block
        #   @return result of a block
        def get(name)
          key = begin
            Object.const_get(name).ancestors.map(&:name).find do |klass_name|
              @strategies.key?(klass_name) || @aliases.key?(klass_name)
            end
          rescue NameError
            name.to_s
          end

          strategy = @strategies[key] || @aliases[key]
          return yield strategy if strategy && block_given?

          strategy
        end

        # @overload each()
        #   @return [Enumerator]
        #
        # @overload each(&block)
        #   @yieldparam [String] name
        #   @yieldparam [Strategy] strategy
        #   @yield [strategy] Gives strategy to the block
        #   @return [Registry]
        def each
          return to_enum(__method__) unless block_given?
          @strategies.each { |*args| yield(*args) }
          self
        end

        # @overload each_with_static_keys()
        #   @return [Enumerator]
        #
        # @overload each_with_static_keys(&block)
        #   @yieldparam [String] name
        #   @yieldparam [Strategy] strategy
        #   @yield [strategy] Gives strategy to the block
        #   @return [Registry]
        def each_with_static_keys
          return to_enum(__method__) unless block_given?
          @strategies.each do |name, strategy|
            yield(name, strategy) unless strategy.dynamic?
          end
        end
      end
    end
  end
end
