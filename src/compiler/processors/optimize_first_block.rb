class OptimizeFirstBlock
  def run(node)
    return false unless first_target = node.blocks[0].jump_block?
    if first_target == node.blocks[1]
      node.blocks[0].remove!
      return true
    end
    false
  end
end
