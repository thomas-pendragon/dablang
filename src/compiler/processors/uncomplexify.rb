class Uncomplexify
  def run(node)
    return unless complex_arg = node.uncomplexify_args.detect(&:complex?)
    id = node.function.allocate_tempvar
    arg_dup = complex_arg.dup
    reg = node.function.allocate_ssa
    setter = DabNodeSSASet.new(arg_dup, reg, id)
    getter = DabNodeSSAGet.new(reg, id)
    node.prepend_instruction(setter)
    complex_arg.replace_with!(getter)
    true
  end
end
