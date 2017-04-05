require_relative 'node.rb'

class DabNodeFunction < DabNode
  attr_reader :identifier
  attr_accessor :arglist_converted

  def initialize(identifier, body, arglist)
    super()
    @identifier = identifier
    insert(body, 'body')
    arglist ||= DabNode.new
    insert(arglist, 'arglist')
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
    children[0]
  end

  def arglist
    children[1]
  end

  def constants
    self.root.constants
  end

  def compile(output)
    @flabel = root.reserve_label
    output.print('LOAD_FUNCTION', @flabel, identifier, parent_class_index, n_local_vars)
  end

  def compile_body(output)
    output.label(@flabel)
    output.print('STACK_RESERVE', n_local_vars)
    body.compile(output)
  end

  def add_constant(literal)
    self.root.add_constant(literal)
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
    "func #{@identifier}(#{fargs})\n{\n" + _indent(body.formatted_source(options)) + "}\n"
  end

  def new_named_codeblock
    label = root.reserve_label
    DabNodeCodeBlock.new(label)
  end

  def remove_localvar_index(index)
    visit_all([DabNodeSetLocalVar, DabNodeLocalVar]) do |node|
      if node.index > index
        node.index -= 1
      end
    end
  end
end
