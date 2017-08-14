class FlattenTreeBlock
  def run(node)
    return unless node.topmost?

    blocks = DabNodeFlatBlock.new

    current_block = DabNodeBasicBlock.new
    blocks << current_block

    node.build_from_tree(current_block, blocks)

    node.replace_with!(blocks)
    true
  end
end
