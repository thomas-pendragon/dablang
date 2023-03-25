class ExtractCallBlock
  def run(node)
    return false unless node.has_block?
    return false if node.block.is_a?(DabNodeBlockReference)

    block = node.block

    root = node.root
    name = 'call'
    klass_name = root.new_blockclass_name(node.function)

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
      # ap ['hmm', identifier]
      value = DabNodeClosureVar.new(index)
      capture_args << DabNodeLocalVar.new(identifier)
      capture_extract << DabNodeDefineLocalVar.new(identifier, value)
    end

    # has_capture = capture_args.count > 0
    # errap ['capture_args',capture_args.dump,has_capture]

    # if has_capture
    #   id = node.function.allocate_tempvar
    #   capture = DabNodeLiteralArray.new(capture_args)
    #   reg = node.function.allocate_ssa
    #   capture_setter = DabNodeSSASet.new(capture, reg, id)
    #   capture_getter = DabNodeSSAGet.new(reg, id)
    # end

    fun = DabNodeFunction.new(name, new_body, arglist, false)
    functions = [fun]
    base_class = 'Method'
    klass = DabNodeClassDefinition.new(klass_name, base_class, functions)

    root.add_class(klass)
    # node.block_capture.replace_with!(capture_getter) if has_capture

    init = DabNodeClass.new(klass_name)
    #  def initialize(value, identifier, arglist, block)
    # errap ['capture_args',capture_args]
    initcall = DabNodeInstanceCall.new(init, 'new', capture_args, nil)

    node.replace_with!(initcall) # DabNodeBlockReference.new(fun))
    # node.prepend_instruction(capture_setter) if has_capture

    klass.run_init!
    fun.run_init!

    # root.dump
    # raise 'a'

    true
  end
end
