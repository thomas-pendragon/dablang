require_relative 'node.rb'

class DabNodeFunction < DabNode
  attr_accessor :n_local_vars
  attr_reader :identifier

  def initialize(identifier, body, arglist)
    super()
    @identifier = identifier
    insert(body)
    insert(DabNode.new)
    insert(arglist)
    self.n_local_vars = 0
    arglist&.each_with_index do |arg, index|
      body.pre_insert(DabNodeDefineLocalVar.new(arg.dup, DabNodeArg.new(index)))
    end
  end

  def extra_dump
    identifier
  end

  def body
    children[0]
  end

  def constants
    children[1]
  end

  def arglist
    children[2]
  end

  def add_constant(literal)
    index = self.constants.count
    const = DabNodeConstant.new(literal, index)
    self.constants.insert(const)
    DabNodeConstantReference.new(index)
  end

  def remove_constant_node(node)
    constants.remove_child(node)
  end

  def compile(output)
    output.function(identifier, n_local_vars) do
      constants.each do |constant|
        constant.compile(output)
      end
      body.compile(output)
    end
  end
end
