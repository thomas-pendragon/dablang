class FlattenIf
  def run(node)
    node.parent.splice(node) do |continue_block|
      node.if_true.insert(DabNodeJump.new(continue_block))
      node.if_false&.insert(DabNodeJump.new(continue_block))
      condition_block = DabNodeCodeBlock.new
      ifjump = DabNodeConditionalJump.new(node.condition, node.if_true, node.if_false || continue_block)
      condition_block.insert(ifjump)
      [condition_block, node.if_true, node.if_false].compact
    end
    true
  end
end
