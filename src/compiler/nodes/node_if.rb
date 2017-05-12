require_relative 'node.rb'
require_relative '../processors/optimize_constant_if.rb'

class DabNodeIf < DabNode
  optimize_with OptimizeConstantIf

  def initialize(condition, if_true, if_false)
    super()
    insert(condition, 'condition')
    insert(if_true, 'true')
    insert(if_false, 'false') if if_false
  end

  def condition
    children[0]
  end

  def if_true
    children[1]
  end

  def if_false
    children[2]
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
    ret += ';'
    ret
  end

  def blockish?
    true
  end

  def unblockify!(continue_block)
    if_true.insert(DabNodeJump.new(continue_block))
    jump_true = if_true.convert_block!
    if if_false
      if_false.insert(DabNodeJump.new(continue_block))
      jump_false = if_false.convert_block!
    else
      jump_false = continue_block
    end
    DabNodeConditionalJump.new(condition, jump_true, jump_false)
  end
end
