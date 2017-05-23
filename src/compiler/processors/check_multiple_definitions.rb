class CheckMultipleDefinitions
  def run(node)
    return unless node.var_definitions.count > 1
    node.add_error(DabCompileMultipleDefinitionsError.new(node.original_identifier, node))
    true
  end
end
