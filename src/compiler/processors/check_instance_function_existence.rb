class CheckInstanceFunctionExistence
  def run(node)
    value = node.value
    type = value.my_type
    identifier = node.real_identifier.to_s
    return unless type.concrete?

    if klass = value.my_class_type
      # errap ['test for', identifier, 'in', klass]
      return if klass.has_class_function?(identifier)
    elsif type.has_function?(identifier)
      return
    end

    klass = type.type_string
    node.add_error(DabCompileUnknownMemberFunctionError.new(klass, identifier, node))

    true
  end
end
