require_relative 'node.rb'
require_relative '../processors/convert_arg_to_localvar.rb'
require_relative '../processors/optimize_first_block.rb'
require_relative '../processors/strip_unused_function.rb'
require_relative '../processors/add_missing_return.rb'
require_relative '../processors/block_reorder.rb'

class DabNodeFunction < DabNode
  attr_accessor :identifier
  attr_reader :inline

  after_init ConvertArgToLocalvar
  after_init AddMissingReturn
  lower_with BlockReorder
  optimize_with OptimizeFirstBlock
  strip_with StripUnusedFunction

  def initialize(identifier, body, arglist, inline, attrlist = nil)
    super()
    @identifier = identifier
    insert(arglist || DabNode.new, 'arglist')
    insert(DabNodeBlockNode.new, 'blocks')
    insert(attrlist) if attrlist
    blocks.insert(body)
    @concrete = false
    @inline = inline
    @autovars = 0
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
    ret = identifier
    ret += ' [flat]' if flat?
    ret
  end

  def argcount
    arglist.count
  end

  def arglist
    children[0]
  end

  def blocks
    children[1]
  end

  def attrlist
    children[2]
  end

  def constants
    self.root.constants
  end

  def funclabel
    'F' + identifier.gsub('=', '%EQ')
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
      compile_function_description(output, DabTypeObject.new)
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
    count = 0
    visit_all(DabNodeDefineLocalVar) do
      count += 1
    end
    count
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
    all_nodes(DabNodeDefineLocalVar).index(var)
  end

  def arg_type(index)
    arglist[index].my_type
  end

  def concreteify(types)
    return self if @concrete
    new_name = "__#{identifier}_#{types.map(&:type_string).join('_')}"
    return new_name if root.has_function?(new_name)
    ret = dup
    ret.identifier = new_name
    ret.arglist.each_with_index do |argdef, index|
      argdef.my_type = types[index]
    end
    root.add_function(ret)
    new_name
  end

  def block_index(block)
    blocks.children.index(block)
  end

  def users
    root.all_nodes(DabNodeBasecall).select { |node| node.target_function == self }
  end

  def flat?
    all_nodes(DabNodeCodeBlock).none?(&:embedded?)
  end
end
