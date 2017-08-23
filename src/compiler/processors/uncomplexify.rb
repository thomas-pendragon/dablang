class Uncomplexify
  def run(node)
    return unless complex_arg = node.uncomplexify_args.detect(&:complex?)
    id = node.function.allocate_tempvar
    arg_dup = complex_arg.dup
    setter = DabNodeDefineLocalVar.new(id, arg_dup)
    getter = DabNodeLocalVar.new(id)
    node.prepend_in_parent(setter)
    complex_arg.replace_with!(getter)
    true
  end
end
