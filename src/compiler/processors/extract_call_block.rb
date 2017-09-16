class ExtractCallBlock
  def run(node)
    return false unless node.has_block?
    return false if node.block.is_a?(DabNodeBlockReference)

    block = node.block

    name = node.function.new_block_name

    block.dump
    arglist = block.arglist&.dup
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

    has_capture = capture_args.count > 0
    if has_capture
      id = node.function.allocate_tempvar
      capture = DabNodeLiteralArray.new(capture_args)
      reg = node.function.allocate_ssa
      capture_setter = DabNodeSSASet.new(capture, reg, id)
      capture_getter = DabNodeSSAGet.new(reg, id)
    end

    fun = DabNodeFunction.new(name, new_body, arglist, false)

    node.root.add_function(fun)
    node.block_capture.replace_with!(capture_getter) if has_capture
    node.block.replace_with!(DabNodeBlockReference.new(fun))
    node.prepend_instruction(capture_setter) if has_capture

    fun.run_init!

    true
  end
end
