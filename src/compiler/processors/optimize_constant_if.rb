class OptimizeConstantIf
  def run(node)
    return unless node.condition.constant?

    test = node.condition.constant_value
    if_true = node.if_true
    if_false = node.if_false
    if_true = if_true.extract
    if_false = if_false&.extract
    node.replace_with!(test ? if_true : if_false)
    true
  end
end
