class LowerIf
  def run(node)
    if_true = node.if_true
    if_false = node.if_false
    condition = node.condition

    if_block = node.function.new_named_codeblock
    true_block = node.function.new_named_codeblock
    false_block = node.function.new_named_codeblock
    continue_block = node.function.new_named_codeblock

    true_block.insert(if_true)
    false_block.insert(if_false) if if_false

    jmp_false = DabNodeJump.new(if_false ? false_block.label : continue_block.label, condition)
    jmp_continue = DabNodeJump.new(continue_block.label)

    true_block.insert(jmp_continue)

    if_block.insert(jmp_false)
    if_block.insert(true_block)
    if_block.insert(false_block) if if_false
    if_block.insert(continue_block)

    node.replace_with!(if_block)
    true
  end
end
