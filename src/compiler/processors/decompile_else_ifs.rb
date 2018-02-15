class DecompileElseIfs
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

      next unless if_true_count == 1

      true_jumps = if_true.all_nodes(DabNodeBaseJump)

      next unless true_jumps.count == 1

      true_jump = true_jumps[0]

      next unless true_jump.is_a?(DabNodeJump)

      next unless true_jump.target.block_index == jump_index + 3

      condition = condition.extract

      new_block_true = DabNodeTreeBlock.new
      new_block_false = DabNodeTreeBlock.new

      nodes_true = if_true.map { |xn| xn } # TODO: to method
      nodes_false = if_false.map { |xn| xn }

      nodes_true.each { |n| new_block_true << n.extract }
      nodes_false.each { |n| new_block_false << n.extract }

      if_block = DabNodeIf.new(condition, new_block_true, new_block_false)
      if_true << if_block

      jump.remove!
      true_jump.remove!

      return true
    end
    false
  end
end
