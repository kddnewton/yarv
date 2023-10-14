# frozen_string_literal: true

require_relative "test_helper"

module YARV
  class CompileTest < Minitest::Test
    Dir[File.join(RbConfig::CONFIG["libdir"], "**", "*.rb")].each do |filepath|
      define_method("test_#{filepath}") do
        assert_compiles(filepath)
      end
    end

    private

    def assert_compiles(filepath)
      $VERBOSE, previous = nil, $VERBOSE

      begin
        YARV.compile_file(filepath)
      ensure
        $VERBOSE = previous
      end
    end
  end
end
