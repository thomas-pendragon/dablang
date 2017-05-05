require_relative '../../shared/base_context.rb'

class DabContext < DabBaseContext
  attr_accessor :local_vars
  attr_accessor :functions
  attr_accessor :classes

  def initialize(stream)
    super(stream)
    @local_vars = []
    @classes = %w(String Fixnum Array)
  end

  def add_local_var(id)
    raise "id must be string, is #{id.class}" unless id.is_a? String
    @local_vars << id
  end

  def add_class(id)
    raise "id must be string, is #{id.class}" unless id.is_a? String
    @classes << id
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
        raise 'unknown token'
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
    list.children.map(&:value).each { |item| ret.insert(item) }
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

      ret = DabNodeArgDefinition.new(-1, id, type)
      ret.add_source_part(id)
      ret.add_source_part(lbrace)
      ret.add_source_part(type)
      ret.add_source_part(rbrace)
      ret
    end
  end

  def read_arglist
    list = _read_simple_list(:read_argument)
    if list
      list.each_with_index do |item, index|
        item.index = index
      end
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
    on_subcontext do |subcontext|
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

  def read_function
    on_subcontext do |subcontext|
      next unless keyw = subcontext.read_keyword('func')
      next unless ident = subcontext.read_identifier_fname
      next unless op1 = subcontext.read_operator('(')
      if arglist = subcontext.read_arglist
        arglist.each do |arg|
          symbol = arg.identifier
          subcontext.add_local_var(symbol)
        end
      end
      next unless op2 = subcontext.read_operator(')')
      next unless code = subcontext.read_codeblock
      ret = DabNodeFunction.new(ident, code, arglist)
      ret.add_source_parts(keyw, ident, op1, op2)
      ret
    end
  end

  def read_identifier_fname
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

  def read_instruction
    read_return || read_define_var || read_call || read_complex_setter
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
    read_localvar_reference || read_instvar_reference
  end

  def read_localvar_reference
    on_subcontext do |subcontext|
      id = subcontext.read_identifier
      next unless @local_vars.include?(id)
      DabNodeReferenceLocalVar.new(id)
    end
  end

  def read_instvar_reference
    on_subcontext do |subcontext|
      next unless id = subcontext.read_classvar
      DabNodeReferenceInstVar.new(id)
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
        DabNodeClass.new(id)
      else
        false
      end
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
      ret = DabNodeCall.new(id, valuelist)
      ret.add_source_part(id)
      ret.add_source_part(op1)
      ret.add_source_part(valuelist)
      ret.add_source_part(op2)
      ret
    end
  end

  def read_codeblock
    on_subcontext do |subcontext|
      next unless subcontext.read_operator('{')
      ret = DabNodeCodeBlock.new
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
    read_if || read_instruction_with_separator
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

  def read_literal_number
    on_subcontext do |subcontext|
      str = subcontext.read_number
      next unless str
      ret = DabNodeLiteralNumber.new(str.to_i)
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
    read_extended_literal || read_literal_string || read_literal_number || read_literal_boolean || read_literal_nil
  end

  def read_instvar
    on_subcontext do |subcontext|
      next unless id = subcontext.read_classvar
      DabNodeClassVar.new(id)
    end
  end

  def read_base_value
    read_instvar || read_self || read_class || read_literal_value || read_local_var || read_call
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
      value
    end
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
        next DabNodeInstanceCall.new(base_value, prop_name, arglist)
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
      next DabNodeInstanceCall.new(base_value, :[], [value])
    end
  end

  def read_postfix(base_value)
    read_dot_postfix(base_value) || read_array_get_postfix(base_value)
  end

  def read_mul_value
    _read_list_or_single(:read_simple_value, ['*', '/', '%'], DabNodeOperator)
  end

  def read_add_value
    _read_list_or_single(:read_mul_value, ['+', '-'], DabNodeOperator)
  end

  def read_or_value
    _read_list_or_single(:read_add_value, ['||', '&&'], DabNodeOperator)
  end

  def read_eq_value
    _read_list_or_single(:read_or_value, ['==', '!='], DabNodeOperator)
  end

  def read_value
    _read_list_or_single(:read_eq_value, ['is'], DabNodeOperator)
  end

  def clone
    ret = super
    ret.local_vars = @local_vars.clone
    ret.classes = @classes.clone
    ret
  end

  def merge!(other_context)
    super(other_context)
    @local_vars = other_context.local_vars
    @functions = other_context.functions
    @classes = other_context.classes
  end
end
