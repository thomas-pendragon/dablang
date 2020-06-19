class ConvertSetValue
  def run(node)
    return if node.value.is_a?(DabNodeCast) # TODO: double cast

    var_type = node.my_type
    value_type = node.value.my_type
    if var_type.requires_cast?(value_type)
      cast_value = DabNodeCast.new(node.value.dup, var_type)
      node.value.replace_with!(cast_value)
      true
    end
  end
end
