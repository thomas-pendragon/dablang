class FoldIsTest
  def run(node)
    left = node.left
    right = node.right
    identifier = node.identifier
    return unless right.constant?

    id = identifier.extra_value
    return unless id == 'is'
    return unless left.my_type.concrete?

    lv = left.my_type
    rv = right.constant_value
    raise "is: rhs must be class, got #{rv.class}" unless rv.is_a? DabType

    value = rv.can_assign_from?(lv)
    node.replace_with!(DabNodeLiteralBoolean.new(value))
    true
  end
end
