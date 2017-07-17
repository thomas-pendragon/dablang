class FlattenWhile
  def run(node)
    node.parent.splice(node) do |continue_block|
      condition_block = DabNodeCodeBlock.new
      ifjump = DabNodeConditionalJump.new(node.condition, node.on_block, continue_block)
      node.on_block.insert(DabNodeJump.new(condition_block))
      condition_block.insert(ifjump)
      [condition_block, node.on_block]
    end
    true
  end
end
