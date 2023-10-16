# frozen_string_literal: true

module YARV
  class Compiler
    attr_reader :options, :encoding
    attr_reader :iseq

    def initialize(options, encoding = Encoding::UTF_8)
      @options = options
      @encoding = encoding

      @iseq = nil
    end

    # alias foo bar
    # ^^^^^^^^^^^^^
    def visit_alias_method_node(node, used)
      iseq.putspecialobject(PutSpecialObject::OBJECT_VMCORE)
      iseq.putspecialobject(PutSpecialObject::OBJECT_CBASE)
      visit(node.new_name, true)
      visit(node.old_name, true)
      iseq.send(YARV.calldata(:"core#set_method_alias", 3), nil)
      iseq.pop unless used
    end

    # alias $foo $bar
    # ^^^^^^^^^^^^^^^
    def visit_alias_global_variable_node(node, used)
      iseq.putspecialobject(PutSpecialObject::OBJECT_VMCORE)
      visit(node.new_name, true)
      visit(node.old_name, true)
      iseq.send(YARV.calldata(:"core#set_variable_alias", 2), nil)
      iseq.pop unless used
    end

    # a and b
    # ^^^^^^^
    def visit_and_node(node, used)
      label = iseq.label

      visit(node.left, true)
      iseq.dup if used
      iseq.branchunless(label)
      iseq.pop if used
      visit(node.right, used)
      iseq.push(label)
    end

    # []
    # ^^
    def visit_array_node(node, used)
      visit_all(node.elements, used)
      iseq.newarray(node.elements.length) if used
    end

    # foo(bar)
    #     ^^^
    def visit_arguments_node(node, used)
      visit_all(node.arguments, used)
    end

    # { a: 1 }
    #   ^^^^
    def visit_assoc_node(node, used)
      visit(node.key, true)
      visit(node.value, true)
    end

    # $+
    # ^^
    def visit_back_reference_read_node(node, used)
      iseq.getspecial(GetSpecial::SVAR_BACKREF, node.slice[1].ord << 1 | 1) if used
    end

    # foo
    # ^^^
    #
    # foo.bar
    # ^^^^^^^
    #
    # foo.bar() {}
    # ^^^^^^^^^^^^
    def visit_call_node(node, used)
      if node.receiver
        visit(node.receiver, true)
      else
        iseq.putself
      end

      argc = 0
      if node.arguments
        argc = node.arguments.arguments.length
        visit(node.arguments, true)
      end

      flags = 0
      flags |= CallData::CALL_FCALL if node.receiver.nil?
      flags |= CallData::CALL_VCALL if node.variable_call?
      flags |= CallData::CALL_ARGS_SIMPLE

      iseq.send(YARV.calldata(node.name, argc, flags), nil)
      iseq.pop unless used
    end

    # class Foo; end
    # ^^^^^^^^^^^^^^
    def visit_class_node(node, used)
      class_iseq = iseq.class_child_iseq(node.name, node.location.start_line)
      with_child_iseq(class_iseq) do
        iseq.event(:RUBY_EVENT_CLASS)
        if node.body
          visit(node.body, true)
        else
          iseq.putnil
        end
        iseq.event(:RUBY_EVENT_END)
        iseq.leave
      end

      flags = DefineClass::TYPE_CLASS
      constant_path = node.constant_path

      if constant_path.is_a?(Prism::ConstantReadNode)
        iseq.putspecialobject(PutSpecialObject::OBJECT_CONST_BASE)
      elsif constant_path.parent.nil?
        flags |= DefineClass::FLAG_SCOPED
        iseq.putobject(Object)
      else
        flags |= DefineClass::FLAG_SCOPED
        visit(constant_path.parent, true)
      end

      if node.superclass
        flags |= DefineClass::FLAG_HAS_SUPERCLASS
        visit(node.superclass, true)
      else
        iseq.putnil
      end

      iseq.defineclass(node.name, class_iseq, flags)
      iseq.pop unless used
    end

    # @@foo
    # ^^^^^
    def visit_class_variable_read_node(node, used)
      iseq.getclassvariable(node.name) if used
    end

    # @@foo = 1
    # ^^^^^^^^^
    def visit_class_variable_write_node(node, used)
      visit(node.value, true)
      iseq.dup if used
      iseq.setclassvariable(node.name)
    end

    # @@foo += bar
    # ^^^^^^^^^^^^
    def visit_class_variable_operator_write_node(node, used)
      iseq.getclassvariable(node.name)
      visit(node.value, true)
      iseq.send(YARV.calldata(node.operator, 1), nil)
      iseq.dup if used
      iseq.setclassvariable(node.name)
    end

    # @@foo &&= bar
    # ^^^^^^^^^^^^^
    def visit_class_variable_and_write_node(node, used)
      label = iseq.label

      iseq.getclassvariable(node.name)
      iseq.dup if used
      iseq.branchunless(label)

      iseq.pop if used
      visit(node.value, true)
      iseq.dup if used
      iseq.setclassvariable(node.name)

      iseq.push(label)
    end

    # @@foo ||= bar
    # ^^^^^^^^^^^^^
    def visit_class_variable_or_write_node(node, used)
      defined_label = iseq.label
      undefined_label = iseq.label

      iseq.putnil
      iseq.defined(Defined::TYPE_CVAR, node.name, true)
      iseq.branchunless(defined_label)

      iseq.getclassvariable(node.name)
      iseq.dup if used
      iseq.branchif(undefined_label)

      iseq.pop if used
      iseq.push(defined_label)
      visit(node.value, true)
      iseq.dup if used
      iseq.setclassvariable(node.name)
      iseq.push(undefined_label)
    end

    # Foo
    # ^^^
    def visit_constant_read_node(node, used)
      iseq.putnil
      iseq.putobject(true)
      iseq.getconstant(node.name) if used
    end

    # Foo::Bar
    # ^^^^^^^^
    def visit_constant_path_node(node, used)
      if node.parent.nil?
        iseq.putobject(Object)
      else
        visit(node.parent, true)
      end

      visit(node.child, true)
    end

    # def foo; end
    # ^^^^^^^^^^^^
    #
    # def self.foo; end
    # ^^^^^^^^^^^^^^^^^
    def visit_def_node(node, used)
      name = node.name
      method_iseq = iseq.method_child_iseq(name.to_s, node.location.start_line)

      with_child_iseq(method_iseq) do
        visit(node.parameters, true) if node.parameters
        if node.body
          iseq.event(:RUBY_EVENT_CALL)
          visit(node.body, true)
        else
          iseq.putnil
        end
        iseq.event(:RUBY_EVENT_RETURN)
        iseq.leave
      end

      if node.receiver
        visit(node.receiver, true)
        iseq.definesmethod(name, method_iseq)
      else
        iseq.definemethod(name, method_iseq)
      end

      iseq.putobject(name) if used
    end

    # defined? a
    # ^^^^^^^^^^
    #
    # defined?(a)
    # ^^^^^^^^^^^
    def visit_defined_node(node, used)
      return unless used
      value = node.value

      case value.type
      when :call_node
        iseq.putself
        iseq.defined(Defined::TYPE_FUNC, value.name, "method")
      when :class_variable_read_node
        iseq.defined(Defined::TYPE_CVAR, value.name, "class variable")
      when :constant_path_node
        if value.parent.nil?
          iseq.putobject(Object)
        else
          visit(value.parent, true)
        end

        iseq.defined(Defined::TYPE_CONST_FROM, value.child.name, "constant")
      when :constant_read_node
        iseq.defined(Defined::TYPE_CONST, value.name, "constant")
      when :false_node
        iseq.putobject("false")
      when :forwarding_super_node
        iseq.putself
        iseq.defined(Defined::TYPE_ZSUPER, false, "super")
      when :global_variable_read_node
        iseq.defined(Defined::TYPE_GVAR, value.name, "global-variable")
      when :local_variable_read_node
        iseq.putobject("local-variable")
      when :local_variable_write_node
        iseq.putobject("assignment")
      when :nil_node
        iseq.putobject("nil")
      when :self_node
        iseq.putobject("self")
      when :true_node
        iseq.putobject("true")
      when :yield_node
        iseq.putnil
        iseq.defined(Defined::TYPE_YIELD, false, "yield")
      else
        iseq.putobject("expression")
      end
    end

    # "foo #{bar}"
    #      ^^^^^^
    def visit_embedded_statements_node(node, used)
      visit(node.statements, used)
    end

    # false
    # ^^^^^
    def visit_false_node(node, used)
      iseq.putobject(false) if used
    end

    # 1.0
    # ^^^
    def visit_float_node(node, used)
      iseq.putobject(node.value) if used
    end

    # for foo in bar do end
    # ^^^^^^^^^^^^^^^^^^^^^
    def visit_for_node(node, used)
      block_iseq = iseq.block_child_iseq(node.location.start_line)
      block_iseq.local_table.plain(:"?")

      with_child_iseq(block_iseq) do
        iseq.getlocal(0, 0)
        visit(node.index, true)
        iseq.event(:RUBY_EVENT_B_CALL)
        iseq.nop

        if node.statements
          visit(node.statements, true)
        else
          iseq.putnil
        end

        iseq.event(:RUBY_EVENT_B_RETURN)
        iseq.leave
      end

      visit(node.collection, true)
      iseq.send(YARV.calldata(:each, 0, 0), block_iseq)
    end

    # $foo
    # ^^^^
    def visit_global_variable_read_node(node, used)
      iseq.getglobal(node.name) if used
    end

    # $foo = 1
    # ^^^^^^^^
    def visit_global_variable_write_node(node, used)
      visit(node.value, true)
      iseq.dup if used
      iseq.setglobal(node.name)
    end

    # $foo += bar
    # ^^^^^^^^^^^
    def visit_global_variable_operator_write_node(node, used)
      iseq.getglobal(node.name)
      visit(node.value, true)
      iseq.send(YARV.calldata(node.operator, 1), nil)
      iseq.dup if used
      iseq.setglobal(node.name)
    end

    # $foo &&= bar
    # ^^^^^^^^^^^^
    def visit_global_variable_and_write_node(node, used)
      label = iseq.label

      iseq.getglobal(node.name)
      iseq.dup if used
      iseq.branchunless(label)

      iseq.pop if used
      visit(node.value, true)
      iseq.dup if used
      iseq.setglobal(node.name)

      iseq.push(label)
    end

    # $foo ||= bar
    # ^^^^^^^^^^^^
    def visit_global_variable_or_write_node(node, used)
      defined_label = iseq.label
      undefined_label = iseq.label

      iseq.putnil
      iseq.defined(Defined::TYPE_GVAR, node.name, true)
      iseq.branchunless(defined_label)

      iseq.getglobal(node.name)
      iseq.dup if used
      iseq.branchif(undefined_label)

      iseq.pop if used
      iseq.push(defined_label)
      visit(node.value, true)
      iseq.dup if used
      iseq.setglobal(node.name)

      iseq.push(undefined_label)
    end

    # {}
    # ^^
    def visit_hash_node(node, used)
      visit_all(node.elements, used)
      iseq.newhash(node.elements.length * 2) if used
    end

    # if foo then bar end
    # ^^^^^^^^^^^^^^^^^^^
    #
    # bar if foo
    # ^^^^^^^^^^
    #
    # foo ? bar : baz
    # ^^^^^^^^^^^^^^^
    def visit_if_node(node, used)
      body_label = iseq.label
      else_label = iseq.label
      done_label = iseq.label

      visit(node.predicate, true)
      iseq.branchunless(else_label)
      iseq.jump(body_label)
      iseq.push(body_label)

      if node.statements
        visit(node.statements, used)
      else
        iseq.putnil if used
      end

      iseq.jump(done_label)
      iseq.pop if used
      iseq.push(else_label)
      iseq.putnil if used
      iseq.push(done_label)
    end

    # 1i
    # ^^
    def visit_imaginary_node(node, used)
      iseq.putobject(node.value) if used
    end

    # { foo: }
    #   ^^^^
    def visit_implicit_node(node, used)
      visit(node.value, used)
    end

    # @foo
    # ^^^^
    def visit_instance_variable_read_node(node, used)
      iseq.getinstancevariable(node.name) if used
    end

    # @foo = 1
    # ^^^^^^^^
    def visit_instance_variable_write_node(node, used)
      visit(node.value, true)
      iseq.dup if used
      iseq.setinstancevariable(node.name)
    end

    # @foo += bar
    # ^^^^^^^^^^^
    def visit_instance_variable_operator_write_node(node, used)
      iseq.getinstancevariable(node.name)
      visit(node.value, true)
      iseq.send(YARV.calldata(node.operator, 1), nil)
      iseq.dup if used
      iseq.setinstancevariable(node.name)
    end

    # @foo &&= bar
    # ^^^^^^^^^^^^
    def visit_instance_variable_and_write_node(node, used)
      label = iseq.label

      iseq.getinstancevariable(node.name)
      iseq.dup if used
      iseq.branchunless(label)

      iseq.pop if used
      visit(node.value, true)
      iseq.dup if used
      iseq.setinstancevariable(node.name)

      iseq.push(label)
    end

    # @foo ||= bar
    # ^^^^^^^^^^^^
    def visit_instance_variable_or_write_node(node, used)
      label = iseq.label

      iseq.getinstancevariable(node.name)
      iseq.dup if used
      iseq.branchif(label)

      iseq.pop if used
      visit(node.value, true)
      iseq.dup if used
      iseq.setinstancevariable(node.name)

      iseq.push(label)
    end

    # 1
    # ^
    def visit_integer_node(node, used)
      iseq.putobject(node.value) if used
    end

    # /foo #{bar}/
    # ^^^^^^^^^^^^
    def visit_interpolated_regular_expression_node(node, used)
      visit_all(node.parts, true)
      iseq.dup
      iseq.objtostring(YARV.calldata(:to_s, 0, CallData::CALL_FCALL | CallData::CALL_ARGS_SIMPLE))
      iseq.anytostring
      iseq.toregexp(node.options, node.parts.length)
      iseq.pop unless used
    end

    # "foo #{bar}"
    # ^^^^^^^^^^^^
    def visit_interpolated_string_node(node, used)
      visit_all(node.parts, true)
      iseq.dup
      iseq.objtostring(YARV.calldata(:to_s, 0, CallData::CALL_FCALL | CallData::CALL_ARGS_SIMPLE))
      iseq.anytostring
      iseq.concatstrings(node.parts.length)
      iseq.pop unless used
    end

    # `foo #{bar}`
    # ^^^^^^^^^^^^
    def visit_interpolated_x_string_node(node, used)
      iseq.putself
      visit_all(node.parts, true)
      iseq.dup
      iseq.objtostring(YARV.calldata(:to_s, 0, CallData::CALL_FCALL | CallData::CALL_ARGS_SIMPLE))
      iseq.anytostring
      iseq.concatstrings(node.parts.length)
      iseq.send(YARV.calldata(:`, 1), nil)
      iseq.pop unless used
    end

    # foo
    # ^^^
    def visit_local_variable_read_node(node, used)
      lookup = iseq.local_table.find!(node.name, node.depth)
      iseq.getlocal(lookup.index, lookup.level) if used
    end

    # foo = 1
    # ^^^^^^^
    def visit_local_variable_write_node(node, used)
      visit(node.value, true)
      iseq.dup if used

      lookup = iseq.local_table.find!(node.name, node.depth)
      iseq.setlocal(lookup.index, lookup.level)
    end

    # foo, = bar
    # ^^^
    def visit_local_variable_target_node(node, used)
      current_iseq = iseq
      node.depth.times { current_iseq = current_iseq.parent_iseq }

      lookup = current_iseq.local_table.find!(node.name, node.depth)
      iseq.setlocal(lookup.index, lookup.level)
    end

    # foo in bar
    # ^^^^^^^^^^
    def visit_match_predicate_node(node, used)
      matched_label = iseq.label
      unmatched_label = iseq.label
      done_label = iseq.label

      iseq.putnil
      visit(node.value, true)
      iseq.dup
      visit(node.pattern, true)
      iseq.checkmatch(CheckMatch::VM_CHECKMATCH_TYPE_CASE)
      iseq.branchif(matched_label)
      iseq.jump(unmatched_label)

      iseq.push(unmatched_label)
      iseq.pop
      iseq.pop
      iseq.putobject(false) if used
      iseq.jump(done_label)

      iseq.putnil
      iseq.putnil unless used
      iseq.push(matched_label)
      iseq.adjuststack(2)
      iseq.putobject(true) if used
      iseq.jump(done_label)

      iseq.push(done_label)
    end

    # /(?<foo>foo)/ =~ bar
    # ^^^^^^^^^^^^^^^^^^^^
    def visit_match_write_node(node, used)
      unmatched_label = iseq.label
      matched_label = iseq.label

      visit(node.call, true)
      iseq.getglobal(:$~)
      iseq.dup
      iseq.branchunless(unmatched_label)

      if node.locals.length == 1
        local = node.locals.first
        iseq.putobject(local)
        iseq.send(YARV.calldata(:[], 1), nil)
        iseq.jump(unmatched_label)

        iseq.push(unmatched_label)
        lookup = iseq.local_table.find!(local, 0)
        iseq.setlocal(lookup.index, lookup.level)
      else
        node.locals.each_with_index do |local, index|
          iseq.dup if index != node.locals.length - 1
          iseq.putobject(local)
          iseq.send(YARV.calldata(:[], 1), nil)

          lookup = iseq.local_table.find!(local, 0)
          iseq.setlocal(lookup.index, lookup.level)
        end
        iseq.jump(matched_label)

        iseq.push(unmatched_label)
        iseq.pop

        node.locals.each do |local|
          iseq.putnil
          lookup = iseq.local_table.find!(local, 0)
          iseq.setlocal(lookup.index, lookup.level)
        end
      end

      iseq.push(matched_label)
      iseq.pop unless used
    end

    # A node that is missing from the syntax tree. This is only used in the
    # case of a syntax error. The parser gem doesn't have such a concept, so
    # we invent our own here.
    def visit_missing_node(node, used)
      raise "Cannot compile missing nodes"
    end

    # module Foo; end
    # ^^^^^^^^^^^^^^^
    def visit_module_node(node, used)
      module_iseq = iseq.module_child_iseq(node.name, node.location.start_line)
      with_child_iseq(module_iseq) do
        iseq.event(:RUBY_EVENT_CLASS)
        if node.body
          visit(node.body, true)
        else
          iseq.putnil
        end
        iseq.event(:RUBY_EVENT_END)
        iseq.leave
      end

      flags = DefineClass::TYPE_MODULE
      constant_path = node.constant_path

      if constant_path.is_a?(Prism::ConstantReadNode)
        iseq.putspecialobject(PutSpecialObject::OBJECT_CONST_BASE)
      elsif constant_path.parent.nil?
        flags |= DefineClass::FLAG_SCOPED
        iseq.putobject(Object)
      else
        flags |= DefineClass::FLAG_SCOPED
        visit(constant_path.parent, true)
      end

      iseq.putnil
      iseq.defineclass(node.name, module_iseq, flags)
      iseq.pop unless used
    end

    # nil
    # ^^^
    def visit_nil_node(node, used)
      iseq.putnil if used
    end

    # $1
    # ^^
    def visit_numbered_reference_read_node(node, used)
      iseq.getspecial(GetSpecial::SVAR_BACKREF, node.number << 1) if used
    end

    # def foo(bar = 1); end
    #         ^^^^^^^
    def visit_optional_parameter_node(node, used)
      index = iseq.local_table.size

      iseq.local_table.plain(node.name)
      iseq.argument_size += 1

      unless iseq.argument_options.key?(:opt)
        start_label = iseq.label
        iseq.push(start_label)
        iseq.argument_options[:opt] = [start_label]
      end

      visit(node.value, true)
      iseq.setlocal(index, 0)

      arg_given_label = iseq.label
      iseq.push(arg_given_label)
      iseq.argument_options[:opt] << arg_given_label
    end

    # a or b
    # ^^^^^^
    def visit_or_node(node, used)
      label = iseq.label

      visit(node.left, true)
      iseq.dup if used
      iseq.branchif(label)
      iseq.pop if used
      visit(node.right, used)
      iseq.push(label)
    end

    # def foo(bar, *baz); end
    #         ^^^^^^^^^
    def visit_parameters_node(node, used)
      visit_all(node.requireds, true)
      visit_all(node.optionals, true)
    end

    # ()
    # ^^
    #
    # (1)
    # ^^^
    def visit_parentheses_node(node, used)
      if node.body
        visit(node.body, used)
      else
        iseq.putnil if used
      end
    end

   # END {}
   # ^^^^^^
   def visit_post_execution_node(node, used)
      start_line = node.location.start_line
      once_iseq = iseq.block_child_iseq(start_line)

      with_child_iseq(once_iseq) do
        postexe_iseq = iseq.block_child_iseq(start_line)

        with_child_iseq(postexe_iseq) do
          iseq.event(:RUBY_EVENT_B_CALL)

          if node.statements
            visit(node.statements, true)
          else
            iseq.putnil
          end

          iseq.event(:RUBY_EVENT_B_RETURN)
          iseq.leave
        end

        iseq.putspecialobject(PutSpecialObject::OBJECT_VMCORE)
        iseq.send(YARV.calldata(:"core#set_postexe", 0, CallData::CALL_FCALL), postexe_iseq)
        iseq.leave
      end

      iseq.once(once_iseq, iseq.inline_storage)
      iseq.pop unless used
    end

    # The top-level program node.
    def visit_program_node(node)
      top_iseq = InstructionSequence.new("<compiled>", "<compiled>", node.location.start_line, :top, nil, options)

      node.locals.each do |local|
        top_iseq.local_table.plain(local)
      end

      with_child_iseq(top_iseq) do
        if node.statements.nil?
          iseq.putnil
        else
          visit(node.statements, true)
        end

        iseq.leave
      end

      top_iseq.compile!
      top_iseq
    end

    # 0..5
    # ^^^^
    def visit_range_node(node, used)
      if node.left
        visit(node.left, used)
      elsif used
        iseq.putnil
      end

      if node.right
        visit(node.right, used)
      elsif used
        iseq.putnil
      end

      iseq.newrange(node.exclude_end? ? 1 : 0) if used
    end

    # 1r
    # ^^
    def visit_rational_node(node, used)
      iseq.putobject(node.value) if used
    end

    # /foo/
    # ^^^^^
    def visit_regular_expression_node(node, used)
      iseq.putobject(Regexp.new(node.unescaped, node.options)) if used
    end

    # def foo(bar); end
    #         ^^^
    def visit_required_parameter_node(node, used)
      iseq.local_table.plain(node.name)
      iseq.argument_size += 1
      iseq.argument_options[:lead_num] ||= 0
      iseq.argument_options[:lead_num] += 1
    end

    # self
    # ^^^^
    def visit_self_node(node, used)
      iseq.putself if used
    end

    # __ENCODING__
    # ^^^^^^^^^^^^
    def visit_source_encoding_node(node, used)
      iseq.putobject(encoding) if used
    end

    # __FILE__
    # ^^^^^^^^
    def visit_source_file_node(node, used)
      iseq.putstring(node.filepath) if used
    end

    # __LINE__
    # ^^^^^^^^
    def visit_source_line_node(node, used)
      iseq.putobject(node.location.start_line) if used
    end

    # A list of statements.
    def visit_statements_node(node, used)
      *statements, last_statement = node.body
      visit_all(statements, false)
      visit(last_statement, used)
    end

    # "foo"
    # ^^^^^
    def visit_string_node(node, used)
      iseq.putstring(node.unescaped) if used
    end

    # :foo
    # ^^^^
    def visit_symbol_node(node, used)
      iseq.putobject(node.unescaped.to_sym) if used
    end

    # true
    # ^^^^
    def visit_true_node(node, used)
      iseq.putobject(true) if used
    end

    # until foo; bar end
    # ^^^^^^^^^^^^^^^^^
    #
    # bar until foo
    # ^^^^^^^^^^^^^
    def visit_until_node(node, used)
      predicate_label = iseq.label
      body_label = iseq.label
      done_label = iseq.label

      iseq.jump(predicate_label)
      iseq.putnil
      iseq.pop
      iseq.jump(predicate_label)

      iseq.push(body_label)
      visit(node.statements, false)

      iseq.push(predicate_label)
      visit(node.predicate, true)
      iseq.branchunless(body_label)

      iseq.jump(done_label)
      iseq.push(done_label)

      iseq.putnil
      iseq.pop unless used
    end

    # while foo; bar end
    # ^^^^^^^^^^^^^^^^^^
    #
    # bar while foo
    # ^^^^^^^^^^^^^
    def visit_while_node(node, used)
      predicate_label = iseq.label
      body_label = iseq.label
      done_label = iseq.label

      iseq.jump(predicate_label)
      iseq.putnil
      iseq.pop
      iseq.jump(predicate_label)

      iseq.push(body_label)
      visit(node.statements, false)

      iseq.push(predicate_label)
      visit(node.predicate, true)
      iseq.branchunless(done_label)

      iseq.jump(body_label)
      iseq.push(done_label)

      iseq.putnil
      iseq.pop unless used
    end

    # `foo`
    # ^^^^^
    def visit_x_string_node(node, used)
      iseq.putself
      iseq.putobject(node.unescaped)
      iseq.send(YARV.calldata(:`, 1, CallData::CALL_FCALL | CallData::CALL_ARGS_SIMPLE), nil)
      iseq.pop unless used
    end

    private

    # Visit a node.
    def visit(node, used)
      public_send("visit_#{node.type}", node, used)
    end

    # Visit a list of nodes.
    def visit_all(nodes, used)
      nodes.map { |node| visit(node, used) }
    end

    # The current instruction sequence that we're compiling is always stored
    # on the compiler. When we descend into a node that has its own
    # instruction sequence, this method can be called to temporarily set the
    # new value of the instruction sequence, yield, and then set it back.
    def with_child_iseq(child_iseq)
      parent_iseq = iseq

      begin
        @iseq = child_iseq
        yield
        child_iseq
      ensure
        @iseq = parent_iseq
      end
    end
  end
end
