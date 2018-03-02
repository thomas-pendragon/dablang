require_relative '../../shared/base_context.rb'

class UnknownTokenException < RuntimeError
  attr_reader :pos
  def initialize(text, pos)
    super(text)
    @pos = pos
  end
end

class SelfOutsideException < RuntimeError
  attr_reader :node
  def initialize(node)
    super()
    @node = node
  end
end

class DabContext < DabBaseContext
  attr_accessor :local_vars
  attr_accessor :functions
  attr_accessor :classes

  def initialize(stream, context)
    super(stream, context)
    @local_vars = []
    @classes = STANDARD_CLASSES.dup
  end

  def add_local_var(id)
    raise "id must be string, is #{id.class}" unless id.is_a? String
    @local_vars << id
  end

  def add_class(id)
    raise "id must be string, is #{id.class}" unless id.is_a? String
    @classes |= [id]
  end

  def raise_unknown_token!
    raise UnknownTokenException.new('Unknown token', @stream.position)
  end

  def raise_self_outside!(node)
    raise SelfOutsideException.new(node)
  end

  def read_program
    ret = DabNodeUnit.new
    until @stream.eof?
      while on_subcontext(&:read_separator)
      end

      if f = on_subcontext(&:read_function)
        ret.add_function(f)
      elsif c = on_subcontext(&:read_define_class)
        ret.add_class(c)
      else
        raise_unknown_token!
      end

      while on_subcontext(&:read_separator)
      end

      @stream.skip_whitespace
    end
    ret
  end

  def _read_list(item_method, separator = ',', accept_extra_separator: false)
    __read_list(item_method, separator, DabNode.new, accept_extra_separator: accept_extra_separator) do |base, item, sep|
      base.insert(DabNodeListNode.new(item, sep))
    end
  end

  def _read_simple_list(item_method, separator = ',', accept_extra_separator: false)
    list = _read_list(item_method, separator, accept_extra_separator: accept_extra_separator)
    return nil unless list
    ret = DabNode.new
    list.map(&:value).each { |item| ret.insert(item) }
    ret
  end

  def _read_list_or_single(method, separator, klass)
    list = _read_list(method, separator)
    return list unless list
    ret = list[0].value
    (list.count - 1).times do |n|
      i = n + 1
      ret = klass.new(ret, list[i].value, list[i].separator)
    end
    ret
  end

  def read_argument
    on_subcontext do |subcontext|
      id = subcontext.read_identifier
      next unless id
      lbrace = subcontext.read_operator('<')
      if lbrace
        next unless type = subcontext.read_type
        next unless rbrace = subcontext.read_operator('>')
      end
      eq = subcontext.read_operator('=')
      if eq
        next unless defvalue = subcontext.read_value
      end

      ret = DabNodeArgDefinition.new(-1, id, type, defvalue)
      ret.add_source_part(id)
      ret.add_source_part(lbrace)
      ret.add_source_part(type)
      ret.add_source_part(rbrace)
      ret
    end
  end

  def read_arglist
    list = _read_simple_list(:read_argument)
    list&.each_with_index do |item, index|
      item.index = index
    end
    list
  end

  def read_type
    on_subcontext do |subcontext|
      typename = subcontext.read_identifier
      next unless typename
      DabNodeType.new(typename)
    end
  end

  def read_define_class
    on_subcontext(new_context: :instance) do |subcontext|
      next unless keyword = subcontext.read_keyword('class')
      next unless ident = subcontext.read_identifier
      if op = subcontext.read_operator(':')
        next unless parent = subcontext.read_identifier
      end
      next unless subcontext.read_operator('{')

      functions = []
      vars = []
      while true
        if func = subcontext.read_function
          functions << func
        elsif ctr = subcontext.read_constructor
          functions << ctr
        elsif dtr = subcontext.read_destructor
          functions << dtr
        elsif var = subcontext.read_class_var_definition
          vars << var
        else
          break
        end
      end

      next unless subcontext.read_operator('}')
      subcontext.add_class(ident)
      ret = DabNodeClassDefinition.new(ident, parent, functions)
      ret.add_source_parts(keyword, ident, op, parent)
      ret
    end
  end

  def read_class_var_definition
    on_subcontext do |subcontext|
      next unless subcontext.read_keyword('var')
      next unless id = subcontext.read_classvar
      next unless subcontext.read_operator(';')
      DabNodeClassVarDefinition.new(id)
    end
  end

  def read_attribute_value
    read_literal_string || read_literal_number
  end

  def read_attribute
    on_subcontext do |subcontext|
      next unless id = subcontext.read_identifier
      if lparen = subcontext.read_operator('(')
        next unless list = subcontext._read_simple_list(:read_attribute_value)
        next unless rparen = subcontext.read_operator(')')
      end
      ret = DabNodeAttribute.new(id, list)
      ret.add_source_parts(lparen, rparen)
      ret
    end
  end

  def read_attrlist
    on_subcontext do |subcontext|
      next unless lparen = subcontext.read_operator('[')
      next unless list = subcontext._read_simple_list(:read_attribute)
      next unless rparen = subcontext.read_operator(']')
      list.add_source_parts(lparen, rparen)
      list
    end
  end

  def read_function
    on_subcontext(merge_local_vars: false) do |subcontext|
      attrlist = subcontext.read_attrlist
      inline = subcontext.read_keyword('inline')
      next unless keyw = subcontext.read_keyword('func')
      next unless ident = subcontext.read_identifier_fname
      if lp = subcontext.read_operator('<')
        next unless rettype = subcontext.read_type
        next unless rp = subcontext.read_operator('>')
      end
      next unless op1 = subcontext.read_operator('(')
      if arglist = subcontext.read_arglist
        arglist.each do |arg|
          symbol = arg.identifier
          subcontext.add_local_var(symbol)
        end
      end
      next unless op2 = subcontext.read_operator(')')
      next unless code = subcontext.read_codeblock
      ret = DabNodeFunction.new(ident, code, arglist, inline, attrlist, rettype)
      ret.add_source_parts(inline, keyw, ident, op1, op2, lp, rettype, rp)
      ret
    end
  end

  def read_constructor
    on_subcontext do |subcontext|
      next unless keyw = subcontext.read_keyword('construct')
      next unless op1 = subcontext.read_operator('(')
      if arglist = subcontext.read_arglist
        arglist.each do |arg|
          symbol = arg.identifier
          subcontext.add_local_var(symbol)
        end
      end
      next unless op2 = subcontext.read_operator(')')
      next unless code = subcontext.read_codeblock
      ret = DabNodeFunction.new('__construct', code, arglist, false)
      ret.add_source_parts(keyw, op1, op2)
      ret
    end
  end

  def read_destructor
    on_subcontext do |subcontext|
      next unless keyw = subcontext.read_keyword('destruct')
      next unless op1 = subcontext.read_operator('(')
      next unless op2 = subcontext.read_operator(')')
      next unless code = subcontext.read_codeblock
      ret = DabNodeFunction.new('__destruct', code, nil, false)
      ret.add_source_parts(keyw, op1, op2)
      ret
    end
  end

  def read_identifier_fname
    read_identifier_fname_regular || read_identifier_fname_op
  end

  def read_identifier_fname_op
    read_any_operator(['==', '!=', '!', '[]=', '[]', '+', '-', '*', '/'])
  end

  def read_identifier_fname_regular
    on_subcontext do |subcontext|
      next unless ident = subcontext.read_identifier
      if op = subcontext.read_operator('=')
        ident += op
      end
      ident
    end
  end

  def read_return
    on_subcontext do |subcontext|
      next unless subcontext.read_keyword('return')
      next unless value = subcontext.read_value

      DabNodeReturn.new(value)
    end
  end

  def read_has_block
    on_subcontext do |subcontext|
      next unless kw = subcontext.read_operator('has_block?')
      ret = DabNodeHasBlock.new
      ret.add_source_parts(kw)
      ret
    end
  end

  def read_yield
    on_subcontext do |subcontext|
      next unless yieldkw = subcontext.read_operator('yield')

      if lparen = subcontext.read_operator('(')
        next unless arglist = subcontext.read_optional_valuelist
        next unless rparen = subcontext.read_operator(')')
      end

      ret = DabNodeYield.new(arglist)
      ret.add_source_parts(yieldkw, lparen, rparen)
      ret
    end
  end

  def _read_reflect(key, read_klass = false)
    on_subcontext do |subcontext|
      next unless kw = subcontext.read_operator(key)

      next unless lparen = subcontext.read_operator('(')
      if read_klass
        next unless klass = subcontext.read_identifier
        next unless comma = subcontext.read_operator(',')
      end
      next unless id = subcontext.read_identifier
      next unless rparen = subcontext.read_operator(')')

      ret = DabNodeReflect.new(key.gsub('reflect_', '').to_sym, id, klass)
      ret.add_source_parts(kw, lparen, rparen, comma)
      ret
    end
  end

  def read_reflect_method_arguments
    _read_reflect('reflect_method_arguments')
  end

  def read_reflect_method_argument_names
    _read_reflect('reflect_method_argument_names')
  end

  def read_reflect_instance_method_argument_types
    _read_reflect('reflect_instance_method_argument_types', true)
  end

  def read_reflect_instance_method_argument_names
    _read_reflect('reflect_instance_method_argument_names', true)
  end

  def read_reflect
    read_reflect_method_arguments ||
      read_reflect_method_argument_names ||
      read_reflect_instance_method_argument_types ||
      read_reflect_instance_method_argument_names
  end

  def read_instruction
    read_yield ||
      read_return ||
      read_define_var ||
      read_call ||
      read_complex_setter ||
      read_value
  end

  def read_complex_setter
    on_subcontext do |subcontext|
      next unless var = subcontext.read_complex_reference
      next unless eq = subcontext.read_operator('=')
      next unless value = subcontext.read_value
      ret = DabNodeSetter.new(var, value)
      ret.add_source_parts(var, eq, value)
      ret
    end
  end

  def read_postfix_reference(base)
    read_index_reference(base) || read_member_reference(base)
  end

  def read_complex_reference
    on_subcontext do |subcontext|
      next unless ref = subcontext.read_simple_reference
      while true
        if postfix = subcontext.read_postfix_reference(ref)
          ref = postfix
        else
          break
        end
      end
      ref
    end
  end

  def read_index_reference(base)
    on_subcontext do |subcontext|
      next unless subcontext.read_operator('[')
      next unless index = subcontext.read_value
      next unless subcontext.read_operator(']')
      DabNodeReferenceIndex.new(base, index)
    end
  end

  def read_member_reference(base)
    on_subcontext do |subcontext|
      next unless subcontext.read_operator('.')
      next unless member = subcontext.read_identifier
      DabNodeReferenceMember.new(base, member)
    end
  end

  def read_simple_reference
    read_self_reference || read_localvar_reference || read_instvar_reference
  end

  def read_localvar_reference
    on_subcontext do |subcontext|
      id = subcontext.read_identifier
      next unless @local_vars.include?(id)
      DabNodeReferenceLocalVar.new(id)
    end
  end

  def read_self_reference
    on_subcontext do |subcontext|
      next unless subcontext.read_operator('self')
      DabNodeReferenceSelf.new
    end
  end

  def read_instvar_reference
    on_subcontext do |subcontext|
      next unless id = subcontext.read_classvar
      DabNodeReferenceInstVar.new(id)
    end
  end

  def read_while
    on_subcontext do |subcontext|
      next unless subcontext.read_keyword('while')
      next unless subcontext.read_operator('(')
      next unless condition = subcontext.read_value
      next unless subcontext.read_operator(')')
      next unless on_block = subcontext.read_codeblock

      DabNodeWhile.new(condition, on_block)
    end
  end

  def read_if
    on_subcontext do |subcontext|
      next unless subcontext.read_keyword('if')
      next unless subcontext.read_operator('(')
      next unless condition = subcontext.read_value
      next unless subcontext.read_operator(')')
      next unless if_true = subcontext.read_codeblock
      elsek = subcontext.read_keyword('else')
      if elsek
        next unless if_false = subcontext.read_codeblock
      end

      DabNodeIf.new(condition, if_true, if_false)
    end
  end

  def read_local_var
    on_subcontext do |subcontext|
      id = subcontext.read_identifier
      if @local_vars.include? id
        DabNodeLocalVar.new(id)
      else
        false
      end
    end
  end

  def read_class
    on_subcontext do |subcontext|
      id = subcontext.read_identifier
      if @classes.include? id
        ret = DabNodeClass.new(id)
        ret.add_source_parts(id)
        ret
      else
        false
      end
    end
  end

  def read_unknown_class
    on_subcontext do |subcontext|
      id = subcontext.read_class_identifier
      next unless id
      ret = DabNodeClass.new(id)
      ret.add_source_parts(id)
      ret
    end
  end

  def read_define_var
    on_subcontext do |subcontext|
      next unless keyw = subcontext.read_keyword('var')
      lbrace = subcontext.read_operator('<')
      if lbrace
        next unless type = subcontext.read_type
        next unless rbrace = subcontext.read_operator('>')
      end
      next unless id = subcontext.read_identifier
      if eq = subcontext.read_operator('=')
        next unless value = subcontext.read_value
      end

      subcontext.add_local_var(id)
      ret = DabNodeDefineLocalVar.new(id, value, type)
      ret.add_source_parts(keyw, lbrace, type, rbrace, id, eq, value)
      ret
    end
  end

  def read_valuelist
    _read_simple_list(:read_value, accept_extra_separator: true)
  end

  def read_optional_valuelist
    read_valuelist || DabNode.new
  end

  def read_call
    on_subcontext do |subcontext|
      next unless id = subcontext.read_identifier
      next unless op1 = subcontext.read_operator('(')
      valuelist = subcontext.read_optional_valuelist
      next unless op2 = subcontext.read_operator(')')
      block = subcontext.read_block

      ret = DabNodeCall.new(id, valuelist, block)
      ret.add_source_part(id)
      ret.add_source_part(op1)
      ret.add_source_part(valuelist)
      ret.add_source_part(op2)
      ret
    end
  end

  def read_block
    on_subcontext do |subcontext|
      next unless op = subcontext.read_operator('^')
      if lparen = subcontext.read_operator('(')
        if arglist = subcontext.read_arglist
          arglist.each do |arg|
            symbol = arg.identifier
            subcontext.add_local_var(symbol)
          end
        end
        next unless rparen = subcontext.read_operator(')')
      end
      next unless block = subcontext.read_codeblock
      ret = DabNodeCallBlock.new(block, arglist)
      ret.add_source_parts(op, lparen, rparen)
      ret
    end
  end

  def read_codeblock
    on_subcontext(merge_local_vars: false) do |subcontext|
      next unless subcontext.read_operator('{')
      ret = DabNodeTreeBlock.new
      while true
        while subcontext.read_separator
        end
        break unless instr = subcontext.read_instruction_line
        while subcontext.read_separator
        end
        ret.insert(instr)
      end
      next unless subcontext.read_operator('}')
      ret
    end
  end

  def read_instruction_line
    read_while ||
      read_if ||
      read_instruction_with_separator ||
      read_codeblock
  end

  def read_separator
    read_operator(';')
  end

  def read_instruction_with_separator
    on_subcontext do |subcontext|
      next unless instr = subcontext.read_instruction
      raise 'expected ;' unless subcontext.read_separator
      instr
    end
  end

  def read_literal_string
    on_subcontext do |subcontext|
      str = subcontext.read_string
      next unless str
      ret = DabNodeLiteralString.new(str)
      ret.add_source_parts(str)
      ret
    end
  end

  def read_literal_float
    on_subcontext do |subcontext|
      str = subcontext.read_float
      next unless str
      ret = DabNodeLiteralFloat.new(str.to_f)
      ret.add_source_part(str)
      ret
    end
  end

  def read_literal_number
    on_subcontext do |subcontext|
      str = subcontext.read_number
      next unless str
      ret = DabNodeLiteralNumber.new(str.to_i)
      ret.add_source_part(str)
      ret
    end
  end

  def read_literal_binary_number
    on_subcontext do |subcontext|
      str = subcontext.read_binary_number
      next unless str
      ret = DabNodeLiteralNumber.new_binary(str)
      ret.add_source_part(str)
      ret
    end
  end

  def read_literal_boolean
    on_subcontext do |subcontext|
      next unless keyword = subcontext.read_any_operator(%w(true false))
      DabNodeLiteralBoolean.new(keyword == 'true')
    end
  end

  def read_literal_nil
    on_subcontext do |subcontext|
      next unless subcontext.read_operator('nil')
      DabNodeLiteralNil.new
    end
  end

  def read_self
    on_subcontext do |subcontext|
      next unless keyword = subcontext.read_operator('self')

      raise_self_outside!(keyword) if self.context != :instance

      ret = DabNodeSelf.new
      ret.add_source_part(keyword)
      ret
    end
  end

  def read_literal_array
    on_subcontext do |subcontext|
      next unless subcontext.read_operator('@')
      next unless subcontext.read_operator('[')
      values = subcontext.read_valuelist
      next unless subcontext.read_operator(']')
      DabNodeLiteralArray.new(values)
    end
  end

  def read_extended_literal
    read_literal_array
  end

  def read_literal_value
    read_extended_literal ||
      read_literal_string ||
      read_literal_binary_number ||
      read_literal_float ||
      read_literal_number ||
      read_literal_boolean ||
      read_literal_nil
  end

  def read_instvar
    on_subcontext do |subcontext|
      next unless id = subcontext.read_classvar
      DabNodeInstanceVar.new(id)
    end
  end

  def read_base_value
    read_instvar ||
      read_self ||
      read_class ||
      read_literal_value ||
      read_local_var ||
      read_call ||
      read_yield ||
      # false
      read_unknown_class
  end

  def read_simple_value_group
    on_subcontext do |subcontext|
      prefix_value = nil
      while true
        if new_prefix_value = subcontext.read_prefix(prefix_value)
          prefix_value = new_prefix_value
        else
          break
        end
      end
      next unless value = subcontext.read_simple_value_group_with_prefix
      value = prefix_value.fixup(value) if prefix_value
      value
    end
  end

  def read_simple_value
    on_subcontext do |subcontext|
      value = subcontext.read_base_value
      next unless value
      while true
        if postfix = subcontext.read_postfix(value)
          value = postfix
        else break
        end
      end
      next value
    end
  end

  def read_parentheses_value
    on_subcontext do |subcontext|
      next unless subcontext.read_operator('(')
      value = subcontext.read_value
      next unless subcontext.read_operator(')')
      value
    end
  end

  def read_simple_value_group_with_prefix
    read_parentheses_value || read_simple_value
  end

  def read_dot_postfix(base_value)
    on_subcontext do |subcontext|
      dot = subcontext.read_operator('.')
      next unless dot
      prop_name = subcontext.read_identifier
      next unless prop_name
      lparen = subcontext.read_operator('(')
      if lparen
        arglist = subcontext.read_optional_valuelist
        next unless arglist
        rparen = subcontext.read_operator(')')
        next unless rparen
        block = subcontext.read_block
        next DabNodeInstanceCall.new(base_value, prop_name, arglist, block)
      else
        next DabNodePropertyGet.new(base_value, prop_name)
      end
    end
  end

  def read_array_get_postfix(base_value)
    on_subcontext do |subcontext|
      next unless subcontext.read_operator('[')
      next unless value = subcontext.read_value
      next unless subcontext.read_operator(']')
      next DabNodeInstanceCall.new(base_value, :[], [value], nil)
    end
  end

  def read_prefix(base_prefix)
    on_subcontext do |subcontext|
      next unless op = subcontext.read_operator('!')
      next DabNodePrefixNode.new(op, base_prefix)
    end
  end

  def read_postfix(base_value)
    read_dot_postfix(base_value) || read_array_get_postfix(base_value)
  end

  def read_mul_value
    _read_list_or_single(:read_simple_value_group, ['*', '/', '%'], DabNodeOperator)
  end

  def read_add_value
    _read_list_or_single(:read_mul_value, ['+', '-'], DabNodeOperator)
  end

  def read_shift_value
    _read_list_or_single(:read_add_value, ['<<', '>>'], DabNodeOperator)
  end

  def read_or_value
    _read_list_or_single(:read_shift_value, ['||', '&&'], DabNodeOperator)
  end

  def read_cmp_value
    _read_list_or_single(:read_or_value, ['<=', '>=', '<', '>'], DabNodeOperator)
  end

  def read_eq_value
    _read_list_or_single(:read_cmp_value, ['==', '!='], DabNodeOperator)
  end

  def read_band_value
    _read_list_or_single(:read_eq_value, ['&'], DabNodeOperator)
  end

  def read_bor_value
    _read_list_or_single(:read_band_value, ['|'], DabNodeOperator)
  end

  def read_value
    read_has_block ||
      read_reflect ||
      _read_list_or_single(:read_bor_value, ['is'], DabNodeOperator)
  end

  def clone(new_context)
    ret = super(new_context)
    ret.local_vars = @local_vars.clone
    ret.classes = @classes.clone
    ret
  end

  def merge!(other_context, merge_local_vars)
    super(other_context)
    @local_vars = other_context.local_vars if merge_local_vars
    @functions = other_context.functions
    @classes = other_context.classes
  end
end
