class ConcreteifyCall
  def run(node)
    return false if node.target_function == true
    return false if node.target_function.concreteified?
    return false unless all_args_concrete?(node)

    concreteify_call!(node)
    true
  end

  def all_args_concrete?(node)
    return false if node.args.count == 0
    return false unless node.target_function.arglist.to_a.all? { |arg| arg.my_type.is_a? DabTypeObject }
    return false unless node.args.all? { |arg| arg.my_type.concrete? }

    true
  end

  def concreteify_call!(node)
    fun = node.target_function.concreteify(node.args.map(&:my_type))
    node.identifier.replace_with!(fun)
    node.mutate!
  end
end
