require_relative 'node_tree_block.rb'
require_relative '../processors/optimize_constant_if.rb'

class DabNodeIf < DabNodeTreeBlock
  optimize_with OptimizeConstantIf

  def initialize(condition, if_true, if_false)
    super()
    insert(condition, 'condition')
    insert(if_true, 'true')
    insert(if_false, 'false') if if_false
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
    ret = 'if (' + condition.formatted_source(options) + ")\n"
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
end
