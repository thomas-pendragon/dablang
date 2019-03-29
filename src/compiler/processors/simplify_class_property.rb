class SimplifyClassProperty
  def run(node)
    return unless node.real_identifier == 'class'
    return unless node.value.my_type.concrete?
    return if node.args.count > 0

    simplified = DabNodeLiteralString.new(node.value.my_type.type_string)
    node.replace_with!(simplified)
    true
  end
end
