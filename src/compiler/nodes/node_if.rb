require_relative 'node.rb'

class DabNodeIf < DabNode
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

  def lower!
    if_block = self.function.new_named_codeblock
    true_block = self.function.new_named_codeblock
    false_block = self.function.new_named_codeblock
    continue_block = self.function.new_named_codeblock

    true_block.insert(if_true)
    false_block.insert(if_false)

    jmp_false = DabNodeJump.new(false_block.label, condition)
    jmp_continue = DabNodeJump.new(continue_block.label)

    true_block.insert(jmp_continue)

    if_block.insert(jmp_false)
    if_block.insert(true_block)
    if_block.insert(false_block)
    if_block.insert(continue_block)

    replace_with!(if_block)
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
end
