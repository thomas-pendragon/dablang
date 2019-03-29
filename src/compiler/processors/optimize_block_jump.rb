class OptimizeBlockJump
  def run(block)
    return if block.block_index == 0
    return unless block.count == 1
    return unless jump = block.ends_with_jump?

    target = jump.target
    return if block == jump.target

    block.function.all_nodes(DabNodeBaseJump).each do |jump2|
      jump2.replace_target!(block, target)
    end
    block.remove!
    true
  end
end
