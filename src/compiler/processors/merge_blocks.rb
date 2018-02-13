class MergeBlocks
  def run(node)
    jump_targets = []

    flat = node.blocks[0]

    old_count = flat.count

    flat.each do |block|
      block.each do |instr|
        if instr.is_a? DabNodeBaseJump
          jump_targets |= instr.targets
        end
      end
    end

    flat = node.blocks[0]

    prev_block = nil

    flat.each do |block|
      if jump_targets.include?(block)
        prev_block = block
        next
      end

      if prev_block
        block.each do |instr|
          prev_block << instr.extract
        end
      else
        prev_block = block
      end
    end

    old_count != flat.count
  end
end
