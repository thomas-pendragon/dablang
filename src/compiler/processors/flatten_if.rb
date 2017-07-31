class FlattenIf
  def run(node)
    node.parent.splice(node) do |continue_block|
      if_true = node.if_true
      if_false = node.if_false
      if_true.insert(DabNodeJump.new(continue_block))
      if_false&.insert(DabNodeJump.new(continue_block))
      condition_block = DabNodeCodeBlock.new
      ifjump = DabNodeConditionalJump.new(node.condition.dup, if_true, if_false || continue_block)
      condition_block.insert(ifjump)
      [condition_block, if_true, if_false].compact
    end
    true
  end
end
