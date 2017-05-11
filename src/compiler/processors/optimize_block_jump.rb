class OptimizeBlockJump
  def run(node)
    node.blocks.each_with_index do |block, index|
      next unless next_block = node.blocks[index + 1]
      next unless jump = block.ends_with_jump?
      target = jump.target
      if target == next_block
        jump.remove!
        return true
      end
    end
    false
  end
end
