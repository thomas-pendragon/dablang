class FixShortcircuit
  def run(operator)
    id = operator.identifier.extra_value.to_s

    return unless id == '&&' || id == '||'

    left = operator.left
    right = operator.right

    left.extract
    right.extract

    left_temp = operator.function.allocate_ssa
    left_tempname = operator.function.allocate_tempvar

    left_set = DabNodeSSASet.new(left, left_temp, left_tempname)
    left_get = DabNodeSSAGet.new(left_temp, left_tempname)

    is_and = id == '&&'

    true_block = DabNodeTreeBlock.new
    false_block = DabNodeTreeBlock.new

    body_block = is_and ? true_block : false_block

    right_temp = operator.function.allocate_ssa
    right_tempname = operator.function.allocate_tempvar

    right_set = DabNodeSSASet.new(right, right_temp, right_tempname)

    body_block << right_set

    phi = DabNodeSSAPhi.new([left_temp, right_temp])

    final_temp = operator.function.allocate_ssa
    final_tempname = operator.function.allocate_tempvar

    final_set = DabNodeSSASet.new(phi, final_temp, final_tempname)
    final_get = DabNodeSSAGet.new(final_temp, final_tempname)

    node_if = DabNodeIf.new(left_get, true_block, false_block)

    operator.prepend_instruction(left_set)
    operator.prepend_instruction(node_if)
    operator.prepend_instruction(final_set)
    operator.replace_with!(final_get)

    true
  end
end
