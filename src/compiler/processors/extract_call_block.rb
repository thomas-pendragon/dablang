class ExtractCallBlock
  def run(node)
    return false unless node.has_block?
    return false if node.block.is_a?(DabNodeBlockReference)

    block = node.block

    root = node.root
    name = '__call'
    klass_name = root.new_blockclass_name(node.function)

    arglist = block.arglist
    body = block.body
    captured_vars = block.captured_variables
    captured_vars_set = block.captured_writable_variables
    capture_args = DabNode.new

    capture_args << DabNodeSelf.new

    block.captured_self.each do |selfnode|
     # selfnode.replace_with!(DabNodeClosureSelf.new)
    end

    (captured_vars + captured_vars_set).each_with_index do |captured_define, index|
      identifier = captured_define.identifier
      value = DabNodeClosureVar.new(index)
      carg = DabNodeLocalVar.new(identifier)
      capture_args << carg
      capture_extract = DabNodeDefineLocalVar.new(identifier, value)
      body.pre_insert(capture_extract)

      captured_define.box!
      capture_extract.closure_box!
      carg.closure_pass!
    end

    fun = DabNodeFunction.new(name, body, arglist, false)
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
