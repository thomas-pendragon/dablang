require_relative 'node.rb'

class DabNodeUnit < DabNode
  attr_reader :constants

  def initialize
    super()
    @functions = DabNode.new
    @constants = DabNode.new
    insert(@functions)
    insert(@constants)
  end

  def add_constant(literal)
    index = @constants.count
    const = DabNodeConstant.new(literal, index)
    @constants.insert(const)
    ret = DabNodeConstantReference.new(index)
    ret.clone_source_parts_from(literal)
    ret
  end

  def add_function(function)
    @functions.insert(function)
  end

  def compile(output)
    (@constants.children + @functions.children).each do |node|
      node.compile(output)
    end
  end

  def remove_constant_node(node)
    @constants.remove_child(node)
  end

  def reorder_constants!
    @constants.children.sort_by!(&:index)
  end
end
