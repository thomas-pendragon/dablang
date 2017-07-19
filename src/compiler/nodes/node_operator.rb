require_relative 'node.rb'
require_relative '../processors/fold_constant.rb'
require_relative '../processors/fold_is_test.rb'

class DabNodeOperator < DabNode
  optimize_with FoldConstant
  optimize_with FoldIsTest

  def initialize(left, right, method)
    super()
    insert(method)
    insert(left)
    insert(right)
  end

  def identifier
    self[0]
  end

  def left
    self[1]
  end

  def right
    self[2]
  end

  def compile(output)
    label = output.next_label

    left.compile(output)
    op_id = identifier.extra_value.to_s
    if op_id == '||' || op_id == '&&'
      output.print('DUP')
      output.print(op_id == '||' ? 'JMP_IF' : 'JMP_IFN', label)
      output.print('POP', 1)
      right.compile(output)
      output.label(label)
    else
      right.compile(output)
      output.push(identifier)
      output.comment("op #{identifier.extra_value}")
      output.print('CALL', 2)
    end
  end

  def formatted_source(options)
    left.formatted_source(options) + " #{identifier.extra_value} " + right.formatted_source(options)
  end
end
