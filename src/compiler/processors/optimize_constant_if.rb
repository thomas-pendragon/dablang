class OptimizeConstantIf
  def run(node)
    return unless node.condition.constant?
    test = node.condition.constant_value
    node.replace_with!(test ? node.if_true : node.if_false)
    true
  end
end
