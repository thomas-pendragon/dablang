class CheckReturnType
  def run(node)
    return_type = node.function.return_type
    value_type = node.my_type
    unless return_type.can_assign_from?(value_type)
      node.add_error(DabCompileReturnTypeError.new(value_type, return_type, node))
      true
    end
  end
end
