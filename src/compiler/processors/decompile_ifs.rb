class DecompileIfs
  def run(node)
    conditional_jumps = node.all_nodes(DabNodeConditionalJump)
    return if conditional_jumps.empty?

    conditional_jumps.each do |jump|
      orignal_jump_block = jump.parent

      condition = jump.condition
      if_true = jump.if_true
      if_false = jump.if_false

      jump_index = orignal_jump_block.block_index
      if_true_index = if_true.block_index
      if_false_index = if_false.block_index

      next unless jump_index + 1 == if_true_index
      next unless jump_index + 2 == if_false_index

      if_true_count = if_true.internal_sources.count
      if_false_count = if_false.internal_sources.count

      next unless if_true_count == 1
      next unless if_false_count == 1

      next unless if_true.all_nodes(DabNodeBaseJump).empty?

      condition = condition.extract

      new_block = DabNodeTreeBlock.new
      nodes = if_true.map { |xn| xn }

      nodes.each { |n| new_block << n.extract }

      if_block = DabNodeIf.new(condition, new_block, nil)
      if_true << if_block

      jump.remove!

      return true
    end
    false
  end
end
