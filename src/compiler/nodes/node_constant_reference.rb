require_relative 'node.rb'
require_relative '../processors/strip_unused_value.rb'
require_relative '../processors/store_locally.rb'

class DabNodeConstantReference < DabNode
  include NodeStoredLocally

  attr_reader :target

  lower_with StripUnusedValue

  def initialize(target)
    super()
    @target = target
  end

  def index
    target.index
  end

  def extra_dump
    "$$#{index} [#{target.extra_value}]"
  end

  def extra_value
    target.extra_value
  end

  def real_value
    target.real_value
  end

  def compile(output)
    output.comment(self.extra_value)
    output.print('PUSH_CONSTANT', self.index)
  end

  def compile_local_set(output, index)
    output.comment(self.extra_value)
    output.print('SETV_CONSTANT', index, self.index)
  end

  def my_type
    target.my_type
  end

  def constant?
    target.constant?
  end
end
