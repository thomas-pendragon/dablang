require_relative 'node'

class DabNodePrefixNode < DabNode
  def initialize(operator, parent_prefix_node)
    super()
    @operator = operator
    @parent_prefix_node = parent_prefix_node
  end

  def fixup(interior_node)
    ret = DabNodeUnaryOperator.new(interior_node, @operator)
    ret = @parent_prefix_node.fixup(ret) if @parent_prefix_node
    ret
  end
end
