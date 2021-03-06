# frozen_string_literal: true

module YARV
  # ### Summary
  #
  # `leave` exits the current frame.
  #
  # ### TracePoint
  #
  # `leave` does not dispatch any events.
  #
  # ### Usage
  #
  # ~~~ruby
  # ;;
  # ~~~
  #
  class Leave < Instruction
    def ==(other)
      other in Leave
    end

    def call(context)
      # skip for now
    end

    def branches?
      true
    end

    def leaves?
      true
    end

    def reads
      1
    end

    def writes
      0
    end

    def side_effects?
      # Leave doesn't really have a side effects... but we say it does so that
      # control flow has somewhere to end up.
      true
    end

    def disasm(iseq)
      "leave"
    end
  end
end
