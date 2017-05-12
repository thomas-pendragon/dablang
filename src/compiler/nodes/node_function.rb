require_relative 'node.rb'
require_relative '../processors/convert_arg_to_localvar.rb'
require_relative '../processors/optimize_first_block.rb'
require_relative '../processors/strip_unused_function.rb'
require_relative '../processors/add_missing_return.rb'

class DabNodeFunction < DabNode
  attr_accessor :identifier
  attr_reader :inline

  after_init ConvertArgToLocalvar
  after_init AddMissingReturn
  optimize_with OptimizeFirstBlock
  strip_with StripUnusedFunction

  def initialize(identifier, body, arglist, inline)
    super()
    @identifier = identifier
    insert(arglist || DabNode.new, 'arglist')
    insert(DabNode.new, 'blocks')
    insert(body, 'body')
    @concrete = false
    @inline = inline
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
    identifier
  end

  def body
    children[2]
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

  def constants
    self.root.constants
  end

  def compile(output)
    @flabel = root.reserve_label
    output.printex(self, 'LOAD_FUNCTION', @flabel, identifier, parent_class_index)
  end

  def compile_body(output)
    output.print("/* f: #{identifier} */")
    output.label(@flabel)
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
    ret = "func #{@identifier}(#{fargs})\n{\n" + _indent(body.formatted_source(options)) + "}\n"
    ret = "inline #{ret}" if inline
    ret
  end

  def new_named_codeblock
    label = root.reserve_label
    DabNodeCodeBlock.new(label)
  end

  def new_codeblock_ex
    label = root.reserve_label
    ret = DabNodeCodeBlockEx.new(label)
    blocks.insert(ret)
    ret
  end

  def blockify!
    if body
      body.blockify!
      children.pop
      true
    else
      super
    end
  end

  def localvar_index(var)
    all_nodes(DabNodeDefineLocalVar).index(var)
  end

  def arg_type(index)
    arglist[index].my_type
  end

  def block_reorder!
    order = [blocks[0].label]
    jump_labels = blocks.flat_map(&:all_jump_labels)
    jump_labels = jump_labels.reverse.uniq.reverse
    order += jump_labels
    my_order = blocks.map(&:label)
    if order != my_order
      blocks.sort_by! do |child|
        order.index(child.label)
      end
      return true
    end
    super
  end

  def concreteify(types)
    return self if @concrete
    # TODO: check if already concreteified
    new_name = "__#{identifier}_#{types.map(&:type_string).join('_')}"
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
end
