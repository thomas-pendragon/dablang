require_relative 'node'
require_relative '../processors/convert_arg_to_localvar'
require_relative '../processors/optimize_first_block'
require_relative '../processors/strip_unused_function'
require_relative '../processors/add_missing_return'
require_relative '../processors/ssaify'
require_relative '../processors/ssa_break_phi_nodes'
require_relative '../processors/reorder_registers'
require_relative '../processors/reorder_registers_incr'

class DabNodeFunction < DabNode
  attr_accessor :identifier
  attr_reader :inline

  after_init :copy_original_body
  after_init ConvertArgToLocalvar
  after_init AddMissingReturn
  # optimize_with OptimizeFirstBlock
  strip_with StripUnusedFunction
  ssa_with SSAify
  post_ssa_with SSABreakPhiNodes
  post_ssa_with ReorderRegisters
  post_ssa_with ReorderRegistersIncr
  unssa_with :unssa!

  attr_accessor :original_body

  attr_accessor :concreteified

  def initialize(identifier, body, arglist, inline = false, attrlist = nil, rettype = nil)
    super()
    @identifier = identifier
    insert(arglist || DabNode.new)
    insert(DabNodeBlockNode.new)
    insert(attrlist || DabNode.new)
    blocks.insert(body)
    @concrete = false
    @inline = inline
    @autovars = 0
    insert(rettype || DabNodeLiteralNil.new)
    @tempvars = 0
    @ssa_count = 0
    @concreteified = false
    insert(DabNodeSymbol.new(identifier))
    argsymbols = DabNode.new
    arglist&.each do |arg|
      argsymbols << DabNodeSymbol.new(arg.identifier)
    end
    insert(argsymbols)
  end

  def children_info
    {
      arglist => 'arglist',
      blocks => 'blocks',
      attrlist => 'attrlist',
    }
  end

  def node_identifier
    self[4]
  end

  def node_arg_symbols
    self[5]
  end

  def rettype
    ret = self[3]
    return nil if ret.is_a? DabNodeLiteralNil

    ret
  end

  def return_type
    self.rettype&.dab_type || DabType.parse(nil)
  end

  def autovar_name
    ret = "%autovar#{@autovars}"
    @autovars += 1
    ret
  end

  def parent_class
    c = parent.parent
    return c if c.is_a? DabNodeClassDefinition

    nil
  end

  def instance_function?
    !!parent_class
  end

  def parent_class_index
    instance_function? ? parent_class.number : -1
  end

  def extra_dump
    identifier + (concreteified? ? ' [concreteified]' : '')
  end

  def argcount
    arglist.count
  end

  def arglist
    self[0]
  end

  def blocks
    self[1]
  end

  def attrlist
    self[2]
  end

  def copy_original_body
    self.original_body = blocks[0].dup
  end

  def constants
    self.root.constants
  end

  def funclabel
    mapping = {
      '=' => 'EQ',
      '!' => 'BANG',
      '[]' => 'INDEX',
      '+' => 'PLUS',
      '-' => 'MINUS',
      '*' => 'MUL',
      '/' => 'DIV',
    }
    mangled_identifier = identifier
    mapping.each do |key, value|
      mangled_identifier = mangled_identifier.gsub(key, "%#{value}")
    end
    ret = "F#{mangled_identifier}"
    if member_function?
      ret = "C#{parent_class.identifier}_#{ret}"
    end
    ret
  end

  def funclabel_end
    "__#{funclabel}_END"
  end

  def create_attribute_init(body)
    attrlist&.each do |attribute|
      arglist = DabNode.new
      arglist << DabNodeMethodReference.new(identifier)
      attribute.arglist&.each do |arg|
        arglist << arg.dup
      end
      call = DabNodeCall.new(attribute.real_identifier, arglist, nil)
      body << call
    end
  end

  def compile_definition(output)
    output.comment(identifier)
    output.print('W_METHOD_EX', node_identifier.symbol_index, parent_class_index, funclabel, arglist.count)
    output.print('W_METHOD_LEN', "#{funclabel_end} - #{funclabel}")
    arglist.each_with_index do |arg, index|
      klass_name = arg.my_type.type_string
      klass = root.class_number(klass_name)
      symbol = node_arg_symbols[index].symbol_index
      output.comment("#{arg.identifier}<#{klass_name}>")
      output.print('W_METHOD_ARG', symbol, klass)
    end
    klass_name = return_type.type_string
    klass = root.class_number(klass_name)
    output.comment("$ret<#{klass_name}>")
    output.print('W_METHOD_ARG', -1, klass)
  end

  def compile_function_description(output, type)
    identifier = type.type_string
    number = root.class_number(identifier)
    output.print('PUSH_CLASS', number)
  end

  def compile_body(output)
    output.label(funclabel)
    output.print('STACK_RESERVE', n_local_vars)
    blocks.each do |block|
      block.compile(output)
    end
    output.label(funclabel_end)
    output.print('NOP')
  end

  def n_local_vars
    variables.count
  end

  def formatted_source(options)
    fargs = []
    arglist.each do |arg|
      fargs << arg.formatted_source(options)
    end
    fargs = fargs.join(', ')
    ret = if identifier == '__construct'
            'construct'
          elsif identifier == '__destruct'
            'destruct'
          else
            "func #{@identifier}"
          end
    ret += "(#{fargs})\n{\n"
    blocks.each do |block|
      ret += _indent(block.formatted_source(options))
    end
    ret += "}\n"
    ret = "inline #{ret}" if inline
    if attrlist && attrlist.count > 0
      list = attrlist.map { |attr| attr.formatted_source(options) }.join(', ')
      ret = "[#{list}]\n#{ret}"
    end
    ret
  end

  def localvar_index(var)
    variables.index(var)
  end

  def arg_type(index)
    arglist[index].my_type
  end

  def arg_name(index)
    arglist[index].identifier
  end

  def concreteify(types)
    return self if @concrete

    new_name = "__#{identifier}_#{types.map(&:base_type).map(&:type_string).join('_')}"
    return new_name if root.has_function?(new_name)

    ret = DabNodeFunction.new(new_name, self.original_body.dup, arglist.dup, inline, attrlist.dup, rettype&.dup)
    ret.arglist.each_with_index do |argdef, index|
      argdef.my_type = types[index]
    end
    root.add_function(ret)
    ret.concreteified = true
    ret.run_init!
    new_name
  end

  def concreteified?
    concreteified
  end

  def block_index(block)
    blocks.index(block)
  end

  def call_users
    root.all_nodes(DabNodeExternalBasecall).select { |node| node.target_function == self }
  end

  def block_users
    root.all_nodes(DabNodeBlockReference).select { |node| node.real_identifier == self.identifier }
  end

  def attribute_users
    root.all_nodes(DabNodeAttribute).select { |node| node.real_identifier == self.identifier }
  end

  def users
    call_users + block_users + attribute_users
  end

  def allocate_ssa
    ret = @ssa_count
    @ssa_count += 1
    ret
  end

  def variables
    all_nodes(DabNodeDefineLocalVar)
  end

  def allocate_tempvar
    n = @tempvars
    @tempvars += 1
    "$temp#{n}"
  end

  def new_block_name
    num = 1
    while true
      name = self.identifier + "__block#{num}"
      return name unless self.root.has_function?(name)

      num += 1
    end
  end

  def member_function?
    !!parent_class
  end

  def unssa!
    return false if @did_unssa

    registers = all_nodes(DabNodeRegisterSet).map(&:output_register)
    registers.sort.uniq.reverse_each do |reg|
      node = DabNodeDefineLocalVar.new("r#{reg}", DabNodeLiteralNil.new)
      blocks[0].pre_insert(node)
    end
    @did_unssa = true
    true
  end

  def nondefault_args
    arglist.map { |x| x }.select { |arg| arg.default_value.nil? }
  end

  def min_argc
    nondefault_args.count
  end

  def max_argc
    arglist.count
  end
end
