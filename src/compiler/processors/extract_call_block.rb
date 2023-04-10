class ExtractCallBlock
  def run(node)
    return false unless node.has_block?
    return false if node.block.is_a?(DabNodeBlockReference)

    block = node.block

    root = node.root
    name = 'call'
    klass_name = root.new_blockclass_name(node.function)

    arglist = block.arglist
    body = block.body
    captured_vars = block.captured_variables
    captured_vars_set = block.captured_writable_variables
    capture_args = DabNode.new

    capture_args << DabNodeSelf.new
    createarglist = DabNode.new
    createbody = DabNodeTreeBlock.new
    createarglist << DabNodeArgDefinition.new(0, 'arg_self', nil, nil)

    createbody << DabNodeSetInstVar.new('@self', DabNodeArg.new(0, nil))

    block.captured_self.each do |selfnode|
      selfnode.replace_with!(DabNodeClosureSelf.new)
    end

    block.captured_instvars.each(&:use_self_proxy!)

    # block.dump

    arraylist = DabNode.new

    i = 1
    (captured_vars + captured_vars_set).each_with_index do |captured_define, index|
      identifier = captured_define.identifier
      value = DabNodeClosureVar.new(index)
      carg = DabNodeLocalVar.new(identifier)
      capture_args << carg
      capture_extract = DabNodeDefineLocalVar.new(identifier, value)
      createarglist << DabNodeArgDefinition.new(i, "arg_#{identifier}", nil, nil)
      arraylist << DabNodeArg.new(i, nil)
      i += 1
      body.pre_insert(capture_extract)

      captured_define.box!
      capture_extract.closure_box!
      carg.closure_pass!
    end

    createbody << DabNodeSetInstVar.new('@closure', DabNodeLiteralArray.new(arraylist))

    # method_class.add_reg_function("__construct", [](DabValue self, std::vector<DabValue> args) {
    # DabValue array_class = $VM->classes[CLASS_ARRAY];
    # DabValue value       = array_class.create_instance();
    # auto    &array       = value.array();
    # bool first = true;
    # DabValue selfnode;
    # for (auto arg : args) {
    #     if (first) {
    #         selfnode = arg;
    #         first = false;
    #     } else {
    #         array.push_back(arg);
    #     }
    # }
    # self.set_instvar($VM->get_or_create_symbol_index("self"), selfnode);
    # self.set_instvar($VM->get_or_create_symbol_index("closure"), value);
    # return nullptr;

    # DabNodeArgDefinition.new(-1, id, type, defvalue)
    # DabNodeArgDefinition.new(index, identifier, type, default_value)

    fun = DabNodeFunction.new(name, body, arglist, false)
    create = DabNodeFunction.new('__construct', createbody, createarglist, false)
    functions = [fun, create]
    base_class = 'Method'
    klass = DabNodeClassDefinition.new(klass_name, base_class, functions)

    root.add_class(klass)

    init = DabNodeClass.new(klass_name)
    initcall = DabNodeInstanceCall.new(init, 'new', capture_args, nil)

    node.replace_with!(initcall)

    true
  end
end
