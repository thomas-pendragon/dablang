class MergeBlocks
  def run(node)
    jump_targets = []

    flat = node.blocks[0]

    flat.each do |block|
      instr = block[0]
      if instr.is_a? DabNodeBaseJump
        jump_targets |= instr.targets
      end
    end

    flat = node.blocks[0]

    prev_block = nil

    flat.each do |block|
      if block.count > 1
        block.dump
        raise 'more than 1 children'
      end

      if jump_targets.include?(block)
        prev_block = block
        next
      end

      if prev_block
        instr = block[0]
        prev_block << instr.extract
      else
        prev_block = block
      end
    end

    # TODO: return status
  end
end
