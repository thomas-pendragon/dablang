class FlattenConditionalJump
  def run(node)
    condition = node.condition
    return unless condition.constant?
    test = condition.constant_value
    node.replace_with!(DabNodeJump.new(test ? node.if_true : node.if_false))
    true
  end
end
