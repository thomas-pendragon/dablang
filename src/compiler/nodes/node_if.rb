require_relative 'node.rb'

class DabNodeIf < DabNode
  def initialize(condition, if_true, if_false)
    super()
    insert(condition)
    insert(if_true)
    insert(if_false) if if_false
    errap 'IF CREATED'
    self.dump
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

  def compile(output)
    label_false = self.function.reserve_label if if_false
    label_end = self.function.reserve_label

    condition.compile(output)
    output.print('JMP_IFN', if_false ? label_false : label_end)

    if_true.compile(output)
    output.print('JMP', label_end)

    if if_false
      output.label(label_false)
      output.print('NOP')
      if_false.compile(output)
    end

    output.label(label_end)
    output.print('NOP')
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
