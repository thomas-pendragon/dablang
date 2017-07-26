class FlattenWhile
  def run(node)
    node.parent.splice(node) do |continue_block|
      condition_block = DabNodeCodeBlock.new
      on_block = node.on_block
      ifjump = DabNodeConditionalJump.new(node.condition, on_block, continue_block)
      on_block.insert(DabNodeJump.new(condition_block))
      condition_block.insert(ifjump)
      [condition_block, on_block]
    end
    true
  end
end
