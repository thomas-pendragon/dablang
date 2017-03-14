require_relative 'node.rb'

class DabNodeFunction < DabNode
  attr_reader :identifier

  def initialize(identifier, body, arglist)
    super()
    @identifier = identifier
    insert(body)
    insert(arglist) if arglist
    arglist&.each_with_index do |arg, index|
      define_var = DabNodeDefineLocalVar.new(arg.identifier, DabNodeArg.new(index, arg.my_type), arg.my_type, true)
      define_var.clone_source_parts_from(arg)
      body.pre_insert(define_var)
    end
    @labels = 0
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

  def reserve_label
    ret = @labels
    @labels += 1
    "L#{ret}"
  end

  def compile(output)
    output.function(identifier, parent_class_index, n_local_vars) do
      body.compile(output)
      output.print('PUSH_NIL')
      output.print('RETURN', '1')
    end
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
    "func #{@identifier}()\n{\n" + _indent(body.formatted_source(options)) + "}\n"
  end
end
