class CheckInstanceFunctionExistence
  def run(node)
    value = node.value
    type = value.my_type
    identifier = node.real_identifier.to_s
    return unless type.concrete?
    return if type.has_function?(identifier)

    klass = type.type_string
    node.add_error(DabCompileUnknownMemberFunctionError.new(klass, identifier, node))

    true
  end
end
