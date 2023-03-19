require_relative 'node_tree_block'
require_relative '../processors/optimize_constant_if'

class DabNodeIf < DabNodeTreeBlock
  optimize_with OptimizeConstantIf

  def initialize(condition, if_true, if_false)
    super()
    insert(condition)
    insert(if_true)
    insert(if_false) if if_false
  end

  def children_info
    {
      condition => 'condition',
      if_true => 'if_true',
      if_false => 'if_false',
    }
  end

  def condition
    self[0]
  end

  def if_true
    self[1]
  end

  def if_false
    self[2]
  end

  def formatted_source(options)
    ret = "if (#{condition.formatted_source(options)})\n"
    ret += "{\n"
    ret += _indent(if_true.formatted_source(options))
    ret += '}'
    if if_false
      ret += "\nelse\n{\n"
      ret += _indent(if_false.formatted_source(options))
      ret += '}'
    end
    ret
  end

  def formatted_skip_semicolon?
    true
  end

  def each_previous_scope_with_index(sender, &block)
    list = [condition]
    inside_true = if_true.includes?(sender)
    inside_false = if_false&.includes?(sender)
    unless inside_false
      list << if_true
    end
    if if_false && !inside_true && !inside_false
      list << if_false
    end
    list.each_with_index(&block)
  end

  def build_from_tree(current_block, blocks)
    condition_node = condition
    true_node = if_true
    false_node = if_false

    condition_node.extract
    true_node.extract
    false_node&.extract

    true_block = DabNodeBasicBlock.new
    false_block = DabNodeBasicBlock.new if false_node
    after_block = DabNodeBasicBlock.new

    negative_block = false_node ? false_block : after_block

    jump = DabNodeConditionalJump.new(condition_node, true_block, negative_block)
    current_block << jump

    blocks << true_block
    true_block = true_node.build_from_tree(true_block, blocks)
    true_block << DabNodeJump.new(after_block)

    if false_node
      blocks << false_block
      false_block = false_node.build_from_tree(false_block, blocks)
      false_block << DabNodeJump.new(after_block)
    end

    blocks << after_block
    after_block
  end

  def fixup_ssa(variable, last_setter)
    true_setter = if_true.fixup_ssa(variable, last_setter)
    false_setter = if_false&.fixup_ssa(variable, last_setter)

    _fixup_ssa_setters(variable, last_setter, [true_setter, false_setter])
  end
end
