require_relative 'node_tree_block'

class DabNodeWhile < DabNodeTreeBlock
  def initialize(condition, on_block)
    super()
    insert(condition)
    insert(on_block)
  end

  def children_info
    {
      condition => 'condition',
      on_block => 'on_block',
    }
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
    return on_block.fixup_ssa(variable, last_setter) if on_block.includes?(variable.var_definition)

    temp_value = DabNode.new
    interim_setter = DabNodeSetLocalVar.new(variable.identifier, temp_value)
    loop_setter = on_block.fixup_ssa(variable, interim_setter)

    new_value = DabNodeSSAPhiBase.new([loop_setter, last_setter].compact.uniq)
    interim_setter.value.replace_with!(new_value)

    self.prepend_in_parent(interim_setter)

    extra_phi = DabNodeSSAPhiBase.new([last_setter, interim_setter, loop_setter].compact.uniq)
    extra_setter = DabNodeSetLocalVar.new(variable.identifier, extra_phi)

    self.append_in_parent(extra_setter)

    extra_setter
  end
end
