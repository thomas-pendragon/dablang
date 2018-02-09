class DecompileIfs
  def run(node)
    conditional_jumps = node.all_nodes(DabNodeConditionalJump)
    return if conditional_jumps.empty?

    jump = conditional_jumps.first
    orignal_jump_block = jump.parent

    condition = jump.condition
    if_true = jump.if_true
    if_false = jump.if_false

    if_true_count = if_true.internal_sources.count
    if_false_count = if_false.internal_sources.count

    return unless (if_true_count == 1) && (if_false_count == 2)

    test_block = if_true

    inner_blocks = []
    jump_block = nil

    while true
      inner_blocks << test_block
      test_block = test_block.next_block

      if test_block.count == 1
        test_node = test_block[0]
        if test_node.is_a? DabNodeJump
          if test_node.target == if_false
            jump_block = test_block
            break
          end
        end
      end

      return if test_block.internal_sources.count > 0
    end

    condition = condition.extract

    new_block = DabNodeTreeBlock.new
    members = []
    inner_blocks.each do |inner_block|
      inner_block.each do |member|
        members << member
      end
    end
    members = members.map(&:extract)
    members.each do |member|
      new_block << member
    end

    inner_blocks.each(&:remove!)
    jump_block.remove!

    if_block = DabNodeIf.new(condition, new_block, nil)

    orignal_jump_block.replace_with!(DabNodeBasicBlock.new << if_block)

    true
  end
end
