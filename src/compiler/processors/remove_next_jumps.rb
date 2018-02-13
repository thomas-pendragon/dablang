class RemoveNextJumps
  def run(node)
    flat = node.blocks[0]

    flat.each do |block|
      next_jump = [block.last].compact.detect do |jump|
        block = jump.parent

        jump.is_a?(DabNodeJump) && (jump.target.block_index == block.block_index + 1)
      end

      next unless next_jump

      next_jump.remove!
      return true
    end

    false
  end
end
