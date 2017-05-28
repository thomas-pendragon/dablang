class CheckMultipleDefinitions
  def run(node)
    siblings = node.scoped_sibling_nodes(DabNodeDefineLocalVar, node).select { |item| item.identifier == node.identifier }
    return unless siblings.count > 1
    node.add_error(DabCompileMultipleDefinitionsError.new(node.original_identifier, node))
    true
  end
end
