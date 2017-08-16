class FlattenConditionalJump
  def run(node)
    if node.if_true == node.if_false
      node.replace_with!([node.condition.dup, DabNodeJump.new(node.if_true)])
      return true
    end

    condition = node.condition
    return unless condition.constant?
    test = condition.constant_value
    node.replace_with!(DabNodeJump.new(test ? node.if_true : node.if_false))
    true
  end
end
