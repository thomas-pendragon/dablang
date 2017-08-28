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
    left.formatted_source(options) + " #{identifier.extra_value} " + right.formatted_source(options)
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
    call = DabNodeCall.new(identifier_, DabNode.new << left_ << right_, nil)
    replace_with!(call)
    true
  end
end
