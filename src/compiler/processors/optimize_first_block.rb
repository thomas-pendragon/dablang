class OptimizeFirstBlock
  def run(node)
    return unless node.blocks
    return unless node.blocks[0]
    return unless first_target = node.blocks[0].jump_block?
    if first_target == node.blocks[1]
      node.blocks[0].remove!
      return true
    end
    false
  end
end
