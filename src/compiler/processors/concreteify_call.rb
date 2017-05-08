class ConcreteifyCall
  def run(node)
    return false unless all_args_concrete?(node)
    concreteify_call!(node)
    true
  end

  def all_args_concrete?(node)
    return false if node.target_function == true
    # TODO: WIP, run check first
    (node.args.count > 0) && (node.target_function.arglist.to_a.all? { |arg| arg.my_type.is_a? DabTypeAny }) && (node.target_function.argcount == node.args.count) && (node.args.all? { |arg| arg.my_type.concrete? })
  end

  def concreteify_call!(node)
    fun = node.target_function.concreteify(node.args.map(&:my_type))
    call = DabNodeHardcall.new(fun, node.args.map(&:dup))
    node.replace_with!(call)
  end
end
