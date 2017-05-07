class CheckAssignType
  def run(node)
    setter = node
    definition = node.var_definition
    var_type = definition.my_type
    value_type = setter.value.my_type
    unless var_type.can_assign_from?(value_type)
      setter.add_error(DabCompileSetvarTypeError.new(value_type, var_type, setter))
      true
    end
  end
end
