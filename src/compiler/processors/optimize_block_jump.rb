class OptimizeBlockJump
  def run(node)
    node.blocks.each_with_index do |block, index|
      next unless next_block = node.blocks[index + 1]
      next unless jump = block.ends_with_jump?
      target = jump.target
      next unless target == next_block
      jump.remove!
      if block.empty?
        node.function.visit_all(DabNodeBaseJump) do |jump2|
          jump2.replace_target!(block, next_block)
        end
        block.remove!
      end
      return true
    end
    false
  end
end
