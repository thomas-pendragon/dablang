class Uncomplexify
  def run(node)
    return unless complex_arg = node.uncomplexify_args.detect { |arg| !node.accepts?(arg) }

    # a = node.is_a?(DabNodeRegisterSet)
    # b = !complex_arg.uncomplex_anyway?
    # a = if a then " [REGSET] " else '' end
    # b = if b then " [ANYWAY] " else '' end
    # err ('---complex maybe?' + a + b + '~'*40).yellow

    # return #unless complex_arg #= node.uncomplexify_args.detect { |arg| !node.accepts?(arg) }
    # return if node.is_a?(DabNodeRegisterSet) && !complex_arg.uncomplex_anyway?

    # err ('---complex' + '~'*40).yellow
    # node.dump

    id = node.function.allocate_tempvar
    arg_dup = complex_arg.dup
    reg = node.function.allocate_ssa
    setter = DabNodeSSASet.new(arg_dup, reg, id)
    getter = DabNodeSSAGet.new(reg, id)
    node.prepend_instruction(setter)
    complex_arg.replace_with!(getter)

    # err ('---uncomplex' + '~'*40).red
    # node.dump

    true
  end
end
