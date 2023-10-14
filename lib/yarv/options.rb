# frozen_string_literal: true

module YARV
  # This represents a set of options that can be passed to the compiler to
  # control how it compiles the code. It mirrors the options that can be
  # passed to RubyVM::InstructionSequence.compile, except it only includes
  # options that actually change the behavior.
  class Options
    def initialize(
      frozen_string_literal: false,
      inline_const_cache: true,
      operands_unification: true,
      peephole_optimization: true,
      specialized_instruction: true,
      tailcall_optimization: false
    )
      @frozen_string_literal = frozen_string_literal
      @inline_const_cache = inline_const_cache
      @operands_unification = operands_unification
      @peephole_optimization = peephole_optimization
      @specialized_instruction = specialized_instruction
      @tailcall_optimization = tailcall_optimization
    end

    def to_hash
      {
        frozen_string_literal: @frozen_string_literal,
        inline_const_cache: @inline_const_cache,
        operands_unification: @operands_unification,
        peephole_optimization: @peephole_optimization,
        specialized_instruction: @specialized_instruction,
        tailcall_optimization: @tailcall_optimization
      }
    end

    def frozen_string_literal!
      @frozen_string_literal = true
    end

    def frozen_string_literal?
      @frozen_string_literal
    end

    def inline_const_cache?
      @inline_const_cache
    end

    def operands_unification?
      @operands_unification
    end

    def peephole_optimization?
      @peephole_optimization
    end

    def specialized_instruction?
      @specialized_instruction
    end

    def tailcall_optimization?
      @tailcall_optimization
    end
  end
end
