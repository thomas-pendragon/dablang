class OptimizeBlockJump
  def run(block)
    return unless block.block_index != 0
    return unless block.children.count == 1
    return unless jump = block.ends_with_jump?
    target = jump.target
    block.function.visit_all(DabNodeBaseJump) do |jump2|
      jump2.replace_target!(block, target)
    end
    block.remove!
    true
  end
end
