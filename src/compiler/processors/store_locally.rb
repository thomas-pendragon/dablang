module NodeStoredLocally
end

class StoreLocally
  def run(node)
    return unless $no_autorelease
    return if node.parent.is_a?(DabNodeDefineLocalVar)
    return if node.parent.is_a?(DabNodeSSASet)
    return if node.parent.is_a?(DabNodeRegisterSet)
    return if node.parent.is_a?(DabNodeConstant)

    name = node.function.autovar_name

    definition = DabNodeDefineLocalVar.new(name, node.dup)
    use = DabNodeLocalVar.new(name)

    node.prepend_instruction(definition)
    node.replace_with!(use)

    true
  end
end
