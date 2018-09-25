# frozen_string_literal: true

module RSpec
  module Helpers
    module StubClass
      def stub_class(name, *parent, &block)
        klass = stub_const(name, Class.new(*parent))
        klass.class_eval(&block) if block
        klass
      end
    end
  end
end
