class StoreLocally
  def run(node)
    return unless $no_autorelease
    return if node.parent.is_a?(DabNodeDefineLocalVar)

    name = node.function.autovar_name

    definition = DabNodeDefineLocalVar.new(name, node.dup)
    use = DabNodeLocalVar.new(name)

    node.prepend_instruction(definition)
    node.replace_with!(use)

    true
  end
end