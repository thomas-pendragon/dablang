class OptimizeBlockJumpNext
  def run(block)
    return unless jump = block.ends_with_jump?

    target = jump.target
    next_block = block.next_block
    return unless target == next_block
    return unless next_block.sources.count == 1

    jump.remove!
    block.merge_with!(next_block)
    true
  end
end
