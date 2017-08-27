require_relative 'node.rb'
require_relative '../processors/fold_constant.rb'
require_relative '../processors/fold_is_test.rb'
require_relative '../processors/uncomplexify.rb'
require_relative '../processors/fix_shortcircuit.rb'

class DabNodeOperator < DabNode
  optimize_with FoldConstant
  optimize_with FoldIsTest
  lower_with Uncomplexify
  after_init FixShortcircuit

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

  def uncomplexify_args
    [left, right]
  end

  def compile(output)
    left.compile(output)
    right.compile(output)
    output.push(identifier)
    output.comment("op #{identifier.extra_value}")
    output.print('CALL', 2)
  end

  def formatted_source(options)
    left.formatted_source(options) + " #{identifier.extra_value} " + right.formatted_source(options)
  end

  def complex?
    true
  end
end
