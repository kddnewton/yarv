# frozen_string_literal: true

require "cgi"
require "forwardable"
require "stringio"

require_relative "yarv/options"
require_relative "yarv/basic_block"
require_relative "yarv/calldata"
require_relative "yarv/control_flow_graph"
require_relative "yarv/data_flow_graph"
require_relative "yarv/disassembler"
require_relative "yarv/instruction_sequence"
require_relative "yarv/instructions"
require_relative "yarv/legacy"
require_relative "yarv/local_table"
require_relative "yarv/mermaid"
require_relative "yarv/sea_of_nodes"
require_relative "yarv/vm"

# An object representation of the YARV bytecode.
module YARV
  # Compile the given source into an InstructionSequence.
  def self.compile(source, options = Options.new)
    iseq = RubyVM::InstructionSequence.compile(source, **options)
    InstructionSequence.from(iseq.to_a)
  end

  # Compile and interpret the given source.
  def self.interpret(source, options = Options.new)
    VM.new.run_top_frame(compile(source, **options))
  end
end
