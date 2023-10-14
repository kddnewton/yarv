# frozen_string_literal: true

require_relative "test_helper"

module YARV
  class CompileTest < Minitest::Test
    # Test that we can compile every Ruby file in the lib directory of our
    # current Ruby version.
    Dir[File.join(RbConfig::CONFIG["libdir"], "**", "*.rb")].each do |filepath|
      define_method("test_#{filepath}") do
        assert_compiles(filepath)
      end
    end

    # Test that we have an instruction class for every instruction in the
    # current Ruby version.
    def test_instruction_names
      expected = RubyVM::INSTRUCTION_NAMES.grep_v(/^trace/).map { |name| name.delete("_").downcase }.sort

      actual = ObjectSpace.each_object(YARV::Instruction.singleton_class).map { |cls| cls.name.split("::").last.downcase }.sort
      known = %w[invokebuiltin optinvokebuiltindelegate optinvokebuiltindelegateleave optreverse]

      assert_empty(expected - actual - known)
    end

    private

    def assert_compiles(filepath)
      $VERBOSE, previous = nil, $VERBOSE

      begin
        YARV.compile_file(filepath).to_cfg
      ensure
        $VERBOSE = previous
      end
    end
  end
end
