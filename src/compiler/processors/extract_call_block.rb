class ExtractCallBlock
  def run(node)
    return false unless node.has_block?
    return false if node.block.is_a?(DabNodeBlockReference)

    block = node.block

    root = node.root
    name = 'call'
    klass_name = root.new_blockclass_name(node.function)

    arglist = block.arglist # &.dup
    body = block.body

    captured_vars = block.captured_variables

    new_body = DabNodeTreeBlock.new
    capture_extract = DabNodeTreeBlock.new

    new_body << capture_extract << body

    capture_args = DabNode.new

    captured_vars.each_with_index do |captured_define, index|
      identifier = captured_define.identifier
      value = DabNodeClosureVar.new(index)
      capture_args << DabNodeLocalVar.new(identifier)
      capture_extract << DabNodeDefineLocalVar.new(identifier, value)
    end

    fun = DabNodeFunction.new(name, new_body, arglist, false)
    functions = [fun]
    base_class = 'Method'
    klass = DabNodeClassDefinition.new(klass_name, base_class, functions)

    root.add_class(klass)

    init = DabNodeClass.new(klass_name)
    initcall = DabNodeInstanceCall.new(init, 'new', capture_args, nil)

    node.replace_with!(initcall)

    true
  end
end
