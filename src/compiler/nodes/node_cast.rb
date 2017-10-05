require_relative 'node.rb'
require_relative '../processors/fold_constant_cast.rb'
require_relative '../processors/uncomplexify.rb'

class DabNodeCast < DabNode
  optimize_with FoldConstantCast
  lower_with Uncomplexify

  def initialize(value, target_type)
    super()
    @target_type = target_type
    insert(value)
  end

  def value
    self[0]
  end

  def target_type
    @target_type
  end

  def my_type
    target_type
  end

  def uncomplexify_args
    [value]
  end

  def accepts?(arg)
    arg.register?
  end

  def compile(output)
    value.compile(output)
    output.printex(self, 'CAST', root.class_index(target_type.type_string))
  end
end
