class RemoveNextJumps
  def run(node)
    ret = false

    while true
      next_jump = node.blocks.all_nodes(DabNodeJump).detect do |jump|
        block = jump.parent
        next false if block.count != 1

        jump.target.block_index == block.block_index + 1
      end

      break unless next_jump

      next_jump.parent.remove!
      ret = true
    end

    ret
  end
end
