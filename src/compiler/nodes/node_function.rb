require_relative 'node.rb'
require_relative '../processors/convert_arg_to_localvar.rb'
require_relative '../processors/optimize_first_block.rb'
require_relative '../processors/strip_unused_function.rb'
require_relative '../processors/add_missing_return.rb'
require_relative '../processors/ssaify.rb'
require_relative '../processors/ssa_break_phi_nodes.rb'
require_relative '../processors/reorder_registers.rb'
require_relative '../processors/reorder_registers_incr.rb'

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
    insert(rettype) if rettype
    @tempvars = 0
    @ssa_count = 0
    @concreteified = false
  end

  def children_info
    {
      arglist => 'arglist',
      blocks => 'blocks',
      attrlist => 'attrlist',
    }
  end

  def rettype
    self[3]
  end

  def return_type
    self[3]&.dab_type || DabType.parse(nil)
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
    ret = 'F' + identifier.gsub('=', '%EQ')
    if member_function?
      ret = 'C' + parent_class.identifier + '_' + ret
    end
    ret
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

  def compile(output)
    output.printex(self, 'LOAD_FUNCTION', funclabel, identifier, parent_class_index)
    if $feature_reflection
      return unless parent_class_index == -1 # TODO
      arglist.each do |arg|
        symbol = DabNodeSymbol.new(arg.identifier)
        symbol.compile(output)
        compile_function_description(output, arg.my_type)
      end
      compile_function_description(output, return_type)
      output.printex(self, 'DESCRIBE_FUNCTION', identifier, arglist.count)
    end
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
      ret = '[' + attrlist.map { |attr| attr.formatted_source(options) }.join(', ') + "]\n#{ret}"
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
end
