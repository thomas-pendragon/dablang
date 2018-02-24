require_relative 'node.rb'
require_relative '../processors/fold_constant.rb'
require_relative '../processors/fold_is_test.rb'
require_relative '../processors/uncomplexify.rb'
require_relative '../processors/fix_shortcircuit.rb'

class DabNodeOperator < DabNode
  optimize_with FoldConstant
  optimize_with FoldIsTest
  lower_with Uncomplexify
  late_lower_with :convert_to_call
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

  def formatted_source(options)
    s_left = left.formatted_source(options)
    s_op = " #{identifier.extra_value} "
    s_right = right.formatted_source(options)

    s_left = "(#{s_left})" if left.is_a?(DabNodeOperator)
    s_right = "(#{s_right})" if right.is_a?(DabNodeOperator)

    s_left + s_op + s_right
  end

  def accepts?(arg)
    arg.register?
  end

  def convert_to_call
    identifier_ = identifier.extra_value
    left_ = left
    right_ = right
    left_.extract
    right_.extract
    call = DabNodeInstanceCall.new(left_, identifier_, DabNode.new << right_, nil)
    replace_with!(call)
    true
  end
end
