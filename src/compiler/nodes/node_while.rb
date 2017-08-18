require_relative 'node_tree_block.rb'

class DabNodeWhile < DabNodeTreeBlock
  def initialize(condition, on_block)
    super()
    insert(condition, 'condition')
    insert(on_block, 'true')
  end

  def condition
    self[0]
  end

  def on_block
    self[1]
  end

  def formatted_source(options)
    ret = 'while (' + condition.formatted_source(options) + ")\n"
    ret += "{\n"
    ret += _indent(on_block.formatted_source(options))
    ret += '}'
    ret
  end

  def formatted_skip_semicolon?
    true
  end

  def build_from_tree(current_block, blocks)
    condition_node = condition
    loop_node = on_block

    condition_node.extract
    loop_node.extract

    condition_block = DabNodeBasicBlock.new
    loop_block = DabNodeBasicBlock.new
    after_block = DabNodeBasicBlock.new

    current_block << DabNodeJump.new(condition_block)

    blocks << condition_block

    jump = DabNodeConditionalJump.new(condition_node, loop_block, after_block)
    condition_block << jump

    blocks << loop_block
    loop_block = loop_node.build_from_tree(loop_block, blocks)
    loop_block << DabNodeJump.new(condition_block)

    blocks << after_block
    after_block
  end

  def fixup_ssa(variable, last_setter)
    loop_setter = on_block.fixup_ssa(variable, last_setter)

    _fixup_ssa_setters(variable, last_setter, [loop_setter])
  end
end
